import 'package:supabase_flutter/supabase_flutter.dart';

/// "For review" inbox -- mirrors the web's src/services/review.service.ts,
/// same RPCs and edge function:
///
///   getQueue()      -> get_review_queue(): uncategorized transactions, each
///                      with a suggested category (rule / learned / vendor /
///                      known merchant / income).
///   suggestWithAi() -> suggest-categories edge function: fills in the ones
///                      nothing else could suggest.
///   post()          -> post_reviewed_transactions(): posts the balanced entry
///                      (bank side implied), marks it blue/verified with the
///                      audit hash chain, learns the merchant.
///   setRule()       -> set_categorization_rule(): "always put X in Y".
/// The deposit is exactly an open invoice's balance ("Payment for INV-0007"),
/// or brings in a payment already recorded on an invoice.
class DepositMatch {
  final String? invoiceId;
  final String? paymentId;
  final String invoiceNumber;
  final String? clientName;

  DepositMatch.invoice(Map<String, dynamic> j)
      : invoiceId = j['invoice_id'] as String,
        paymentId = null,
        invoiceNumber = j['invoice_number'] as String,
        clientName = j['client_name'] as String?;

  DepositMatch.payment(Map<String, dynamic> j)
      : invoiceId = null,
        paymentId = j['payment_id'] as String,
        invoiceNumber = j['invoice_number'] as String,
        clientName = null;

  String get label => invoiceId != null
      ? 'Payment for $invoiceNumber${clientName != null ? ' · $clientName' : ''}'
      : 'Deposit of the payment on $invoiceNumber';
}

class ReviewItem {
  final String id;
  final String transactionDate;
  final String? description;
  final String? merchantName;
  final double amount;
  final String currency;
  final String semaphore;
  final String? statusReason;
  final String? suggestedAccountId;
  final String? suggestionSource;
  final int? suggestionConfidence;
  final bool hasReceipt;
  final DepositMatch? match;

  ReviewItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        transactionDate = j['transaction_date'] as String,
        description = j['description'] as String?,
        merchantName = j['merchant_name'] as String?,
        amount = (j['amount'] as num).toDouble(),
        currency = ((j['currency'] as String?) ?? 'USD').trim(),
        semaphore = (j['semaphore'] as String?) ?? 'green',
        statusReason = j['status_reason'] as String?,
        suggestedAccountId = j['suggested_account_id'] as String?,
        suggestionSource = j['suggestion_source'] as String?,
        suggestionConfidence = (j['suggestion_confidence'] as num?)?.toInt(),
        hasReceipt = j['has_receipt'] == true,
        match = j['invoice_match'] is Map<String, dynamic>
            ? DepositMatch.invoice(j['invoice_match'] as Map<String, dynamic>)
            : j['deposit_match'] is Map<String, dynamic>
                ? DepositMatch.payment(j['deposit_match'] as Map<String, dynamic>)
                : null;

  String get label => merchantName ?? description ?? 'Transaction';
  bool get moneyIn => amount > 0;
}

class ReviewQueue {
  final List<ReviewItem> items;
  final int total;

  /// The account the bank side posts to; false = the chart has none yet.
  final bool hasBankAccount;

  ReviewQueue.fromJson(Map<String, dynamic> j)
      : items = ((j['items'] as List?) ?? [])
            .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total = (j['total'] as num?)?.toInt() ?? 0,
        hasBankAccount = j['bank_account'] != null;
}

/// A leaf income/expense account: the only valid categories.
class CategoryAccount {
  final String id;
  final String code;
  final String name;
  final String type; // 'income' | 'expense'

  CategoryAccount({required this.id, required this.code, required this.name, required this.type});

  String get label => '$code · $name';
}

class Suggestion {
  final String accountId;
  final String? source;
  final int? confidence;

  /// Set when the suggestion is the row's invoice / recorded-payment match.
  final DepositMatch? match;
  const Suggestion(this.accountId, this.source, this.confidence, {this.match});
}

class RulePrompt {
  final String merchantKey;
  final String? clientId;
  final String accountId;
  final String accountName;

  RulePrompt.fromJson(Map<String, dynamic> j)
      : merchantKey = j['merchant_key'] as String,
        clientId = j['client_id'] as String?,
        accountId = j['account_id'] as String,
        accountName = j['account_name'] as String;
}

class PostResult {
  final Set<String> posted;
  final Map<String, String> failed; // transaction id -> reason
  final List<RulePrompt> rulePrompts;

  PostResult.fromJson(Map<String, dynamic> j)
      : posted = ((j['posted'] as List?) ?? []).map((e) => e as String).toSet(),
        failed = {
          for (final f in ((j['failed'] as List?) ?? []).cast<Map<String, dynamic>>())
            f['transaction_id'] as String: (f['error'] as String?) ?? 'Could not verify',
        },
        rulePrompts = ((j['rule_prompts'] as List?) ?? [])
            .map((e) => RulePrompt.fromJson(e as Map<String, dynamic>))
            .toList();
}

/// Human label for where a suggestion came from -- same words as the web.
String suggestionSourceLabel(String? source) => switch (source) {
      'rule' => 'Rule',
      'learned' => 'Learned',
      'vendor' => 'Vendor',
      'merchant' => 'Known merchant',
      'invoice' => 'Invoice payment',
      'deposit' => 'Recorded payment',
      'income' => 'Income',
      'ai' => 'AI',
      _ => '',
    };

class ReviewService {
  final _db = Supabase.instance.client;

  Future<ReviewQueue> getQueue(String orgId, String? clientId) async {
    final data = await _db.rpc('get_review_queue', params: {
      'p_org_id': orgId,
      'p_client_id': clientId,
      'p_limit': 100,
    });
    return ReviewQueue.fromJson(data as Map<String, dynamic>);
  }

  /// Leaf income/expense accounts of this scope (a heading with children is
  /// never a category), the same filter the web and the posting RPC apply.
  Future<List<CategoryAccount>> getCategories(String orgId, String? clientId) async {
    var q = _db
        .from('accounts')
        .select('id, code, name, type, parent_id')
        .eq('org_id', orgId)
        .eq('is_active', true);
    q = clientId != null ? q.eq('client_id', clientId) : q.isFilter('client_id', null);
    final rows = (await q.order('code')).cast<Map<String, dynamic>>();
    final parents = rows.map((r) => r['parent_id']).whereType<String>().toSet();
    return rows
        .where((r) => !parents.contains(r['id']) && (r['type'] == 'income' || r['type'] == 'expense'))
        .map((r) => CategoryAccount(
              id: r['id'] as String,
              code: (r['code'] as String?) ?? '',
              name: (r['name'] as String?) ?? '',
              type: r['type'] as String,
            ))
        .toList();
  }

  /// AI suggestions are a bonus: any failure just leaves those rows to the user.
  Future<Map<String, Suggestion>> suggestWithAi(String orgId, String? clientId, List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final res = await _db.functions.invoke('suggest-categories', body: {
        'org_id': orgId,
        'client_id': clientId,
        'transaction_ids': ids.take(25).toList(),
      });
      final list = ((res.data as Map<String, dynamic>?)?['suggestions'] as List?) ?? [];
      return {
        for (final s in list.cast<Map<String, dynamic>>())
          s['transaction_id'] as String:
              Suggestion(s['account_id'] as String, 'ai', (s['confidence'] as num?)?.toInt()),
      };
    } catch (_) {
      return {};
    }
  }

  Future<PostResult> post(String orgId, List<Map<String, dynamic>> items) async {
    final data = await _db.rpc('post_reviewed_transactions', params: {
      'p_org_id': orgId,
      'p_items': items,
    });
    return PostResult.fromJson(data as Map<String, dynamic>);
  }

  Future<void> setRule(String orgId, RulePrompt p) async {
    await _db.rpc('set_categorization_rule', params: {
      'p_org_id': orgId,
      'p_client_id': p.clientId,
      'p_merchant_key': p.merchantKey,
      'p_account_id': p.accountId,
      'p_is_rule': true,
    });
  }
}
