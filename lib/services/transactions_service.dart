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

/// The time window of the dashboard.
enum TxPeriod { days30, days90, thisYear, all }

extension TxPeriodInfo on TxPeriod {
  String get label => switch (this) {
        TxPeriod.days30 => '30 days',
        TxPeriod.days90 => '90 days',
        TxPeriod.thisYear => 'This year',
        TxPeriod.all => 'All time',
      };

  /// First day included, or null for no limit. [now] is injectable for tests.
  DateTime? since([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (this) {
      TxPeriod.days30 => today.subtract(const Duration(days: 30)),
      TxPeriod.days90 => today.subtract(const Duration(days: 90)),
      TxPeriod.thisYear => DateTime(n.year, 1, 1),
      TxPeriod.all => null,
    };
  }
}

/// The three numbers at the top of the dashboard, for the chosen period.
class TxTotals {
  final double moneyIn;
  final double moneyOut; // a positive number: the size of what went out
  final int needsReview; // amber + red
  const TxTotals(this.moneyIn, this.moneyOut, this.needsReview);
}

class TxPage {
  final List<TxItem> rows;

  /// How many transactions each semaphore colour holds across the WHOLE
  /// workspace for the period (not just the loaded page), plus 'all'.
  final Map<String, int> counts;
  final TxTotals totals;
  final bool hasMore;
  const TxPage(this.rows, this.counts, this.totals, this.hasMore);
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
    TxPeriod period = TxPeriod.all,
  }) async {
    final since = period.since();
    final summaryFuture = _summary(orgId, since);

    var q = _db
        .from('transactions')
        .select('id, description, merchant_name, amount, currency, semaphore, '
            'transaction_date, status_reason, source, '
            'clients(display_name, company_name)')
        .eq('org_id', orgId)
        .eq('is_current', true);
    if (since != null) q = q.gte('transaction_date', _isoDay(since));
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
    final summary = await summaryFuture;
    return TxPage(
      hasMore ? list.sublist(0, limit) : list,
      summary.counts,
      summary.totals,
      hasMore,
    );
  }

  static String _isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Counts and totals come from one light query over colour + amount, the way
  /// the web derives them from the rows it holds; capped so a huge ledger
  /// cannot make this slow.
  Future<({Map<String, int> counts, TxTotals totals})> _summary(
      String orgId, DateTime? since) async {
    var q = _db
        .from('transactions')
        .select('semaphore, amount')
        .eq('org_id', orgId)
        .eq('is_current', true);
    if (since != null) q = q.gte('transaction_date', _isoDay(since));
    final rows = await q.limit(10000);
    return summarize((rows as List)
        .map((r) => (
              semaphore: (r as Map)['semaphore'] as String?,
              amount: ((r)['amount'] as num?)?.toDouble() ?? 0,
            ))
        .toList());
  }

  /// Pure: per-colour counts plus money in / out / needs-review. Split out so
  /// it can be tested without a database.
  static ({Map<String, int> counts, TxTotals totals}) summarize(
      List<({String? semaphore, double amount})> rows) {
    final counts = <String, int>{for (final s in semaphores) s: 0};
    var moneyIn = 0.0, moneyOut = 0.0;
    for (final r in rows) {
      final s = r.semaphore;
      if (s != null && counts.containsKey(s)) counts[s] = counts[s]! + 1;
      if (r.amount > 0) {
        moneyIn += r.amount;
      } else {
        moneyOut += -r.amount;
      }
    }
    counts['all'] = counts.values.fold(0, (a, b) => a + b);
    return (
      counts: counts,
      totals: TxTotals(moneyIn, moneyOut, (counts['amber'] ?? 0) + (counts['red'] ?? 0)),
    );
  }

  /// Strips characters that would break out of the PostgREST `or(...)` filter
  /// (commas, parentheses, wildcards) so a search box cannot inject filters.
  static String _cleanSearch(String s) =>
      s.trim().replaceAll(RegExp(r'[,()%*\\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Exposed for tests.
  static String cleanSearchForTest(String s) => _cleanSearch(s);
}
