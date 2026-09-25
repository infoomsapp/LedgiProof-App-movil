import 'package:supabase_flutter/supabase_flutter.dart';

/// One bank / manual transaction as the phone shows it.
class TxItem {
  final String id;
  final String? description;
  final String? merchantName;
  final double amount; // positive = money in, negative = money out
  final String currency;
  final String semaphore; // blue | green | amber | red
  final DateTime date;
  final String? statusReason;
  final String? source; // bank_api | manual | ...
  final String? clientName;

  TxItem.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        description = r['description'] as String?,
        merchantName = r['merchant_name'] as String?,
        amount = (r['amount'] as num?)?.toDouble() ?? 0,
        currency = (r['currency'] as String?) ?? 'USD',
        semaphore = (r['semaphore'] as String?) ?? 'amber',
        date = DateTime.tryParse((r['transaction_date'] as String?) ?? '') ??
            DateTime.now(),
        statusReason = r['status_reason'] as String?,
        source = r['source'] as String?,
        clientName = r['clients'] == null
            ? null
            : ((r['clients'] as Map)['company_name'] as String?) ??
                ((r['clients'] as Map)['display_name'] as String?);

  String get title => merchantName ?? description ?? 'Transaction';
  bool get isBank => source == 'bank_api';
}

class TxPage {
  final List<TxItem> rows;

  /// How many transactions each semaphore colour holds across the WHOLE
  /// workspace (not just the loaded page), plus 'all'.
  final Map<String, int> counts;
  final bool hasMore;
  const TxPage(this.rows, this.counts, this.hasMore);
}

/// Transactions list for the phone -- the same data and the same semaphore
/// filter as the web's Transactions page. What a person sees is decided by the
/// database, not by this class: staff get their organization's rows
/// (transactions_select), a portal client only their own (transactions_client_select).
class TransactionsService {
  final _db = Supabase.instance.client;

  static const semaphores = ['blue', 'green', 'amber', 'red'];

  /// Loads the first [limit] rows for [semaphore] (null = all) matching
  /// [search], newest first, together with the per-colour counts. A removed
  /// bank transaction (is_current = false) never shows.
  Future<TxPage> load(
    String orgId, {
    String? semaphore,
    String search = '',
    int limit = 50,
  }) async {
    final countsFuture = _counts(orgId);

    var q = _db
        .from('transactions')
        .select('id, description, merchant_name, amount, currency, semaphore, '
            'transaction_date, status_reason, source, '
            'clients(display_name, company_name)')
        .eq('org_id', orgId)
        .eq('is_current', true);
    if (semaphore != null) q = q.eq('semaphore', semaphore);
    final term = _cleanSearch(search);
    if (term.isNotEmpty) {
      q = q.or('description.ilike.%$term%,merchant_name.ilike.%$term%');
    }
    // One extra row tells us whether there is a next page.
    final rows = await q
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit + 1);

    final list = (rows as List)
        .map((r) => TxItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
    final hasMore = list.length > limit;
    return TxPage(
      hasMore ? list.sublist(0, limit) : list,
      await countsFuture,
      hasMore,
    );
  }

  /// Counts come from one light query over ids+colours, the way the web
  /// derives them from the rows it holds; capped so a huge ledger cannot make
  /// this slow.
  Future<Map<String, int>> _counts(String orgId) async {
    final rows = await _db
        .from('transactions')
        .select('semaphore')
        .eq('org_id', orgId)
        .eq('is_current', true)
        .limit(10000);
    final counts = <String, int>{for (final s in semaphores) s: 0};
    for (final r in rows as List) {
      final s = (r as Map)['semaphore'] as String?;
      if (s != null && counts.containsKey(s)) counts[s] = counts[s]! + 1;
    }
    counts['all'] = counts.values.fold(0, (a, b) => a + b);
    return counts;
  }

  /// Strips characters that would break out of the PostgREST `or(...)` filter
  /// (commas, parentheses, wildcards) so a search box cannot inject filters.
  static String _cleanSearch(String s) =>
      s.trim().replaceAll(RegExp(r'[,()%*\\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Exposed for tests.
  static String cleanSearchForTest(String s) => _cleanSearch(s);
}
