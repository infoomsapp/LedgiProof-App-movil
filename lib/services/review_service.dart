import 'package:supabase_flutter/supabase_flutter.dart';

/// "For review" inbox -- mirrors the web's src/services/review.service.ts,
/// same RPCs:
///
///   getQueue()      -> get_review_queue(): uncategorized transactions, each
///                      with a suggested category (rule / learned / vendor /
///                      known merchant / income).
///   post()          -> post_reviewed_transactions(): posts the balanced entry
///                      (bank side implied), marks it blue/verified with the
///                      audit hash chain, learns the merchant.
///   setRule()       -> set_categorization_rule(): "always put X in Y".
/// A bank line that settles a document, offered before any category:
///   · a deposit that is exactly an open invoice's balance ("Payment for INV-0007")
///   · a deposit that brings in a payment already recorded on an invoice
///   · a withdrawal that pays an open bill, or is the money of a bill already
///     marked paid ("in transit") -- bills_ledger.sql
class DepositMatch {
  final String? invoiceId;
  final String? paymentId;
  final String? billId;
  final String invoiceNumber; // the invoice or bill number ('' when none)
  final String? clientName;   // the client, or the bill's vendor
  final bool billInTransit;

  DepositMatch.invoice(Map<String, dynamic> j)
      : invoiceId = j['invoice_id'] as String,
        paymentId = null,
        billId = null,
        invoiceNumber = j['invoice_number'] as String,
        clientName = j['client_name'] as String?,
        billInTransit = false;

  DepositMatch.payment(Map<String, dynamic> j)
      : invoiceId = null,
        paymentId = j['payment_id'] as String,
        billId = null,
        invoiceNumber = j['invoice_number'] as String,
        clientName = null,
        billInTransit = false;

  DepositMatch.bill(Map<String, dynamic> j)
      : invoiceId = null,
        paymentId = null,
        billId = j['bill_id'] as String,
        invoiceNumber = (j['bill_number'] as String?) ?? '',
        clientName = j['vendor_name'] as String?,
        billInTransit = j['kind'] == 'in_transit';

  String get label {
    if (billId != null) {
      final number = invoiceNumber.isEmpty ? '' : ' $invoiceNumber';
      return billInTransit
          ? 'Withdrawal of the payment for bill$number · ${clientName ?? 'vendor'}'
          : 'Payment for bill$number · ${clientName ?? 'vendor'}';
    }
    return invoiceId != null
        ? 'Payment for $invoiceNumber${clientName != null ? ' · $clientName' : ''}'
        : 'Deposit of the payment on $invoiceNumber';
  }
}

/// One reason behind a suggestion -- lp_private.suggest_account's evidence
/// (brain_f2_evidence.sql). Fixed points, no AI. Same words as the web's
/// "Why?" (review.why in en.ts).
class BrainEvidence {
  final String signal;
  final int points;
  final String? accountName;
  final String? merchant;
  final int? count;
  final String? category;

  BrainEvidence.fromJson(Map<String, dynamic> j)
      : signal = (j['signal'] as String?) ?? '',
        points = (j['points'] as num?)?.toInt() ?? 0,
        accountName = j['account_name'] as String?,
        merchant = j['merchant'] as String?,
        count = (j['count'] as num?)?.toInt(),
        category = j['category'] as String?;

  String get text {
    final a = accountName ?? '';
    return switch (signal) {
      'rule' => 'Your rule: “$merchant” always goes to $a',
      'learned' => count == 1 ? '“$merchant” confirmed once in $a' : '“$merchant” confirmed $count times in $a',
      'vendor' => "This vendor's default account: $a",
      'merchant' => 'Known merchant: this kind of spending usually goes to $a',
      'bank_category' => 'The bank classifies it as $category',
      'income' => 'Money in: first income account ($a)',
      'agreement' => '$count signals agree',
      'conflict' => 'Could also be $a — take a look',
      _ => '',
    };
  }
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
  final List<BrainEvidence> evidence;
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
        evidence = ((j['suggestion_evidence'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(BrainEvidence.fromJson)
            .where((e) => e.text.isNotEmpty)
            .toList(),
        hasReceipt = j['has_receipt'] == true,
        match = j['invoice_match'] is Map<String, dynamic>
            ? DepositMatch.invoice(j['invoice_match'] as Map<String, dynamic>)
            : j['deposit_match'] is Map<String, dynamic>
                ? DepositMatch.payment(j['deposit_match'] as Map<String, dynamic>)
                : j['bill_match'] is Map<String, dynamic>
                    ? DepositMatch.bill(j['bill_match'] as Map<String, dynamic>)
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
      'bank_category' => "Bank's category",
      'invoice' => 'Invoice payment',
      'deposit' => 'Recorded payment',
      'bill' => 'Bill payment',
      'bill_payment' => 'Recorded bill payment',
      'income' => 'Income',
      _ => '',
    };

/// Already in the books, not verified yet (green = ready, or amber when a
/// rule flagged it). Same rows as the web's VerifyQueue, from
/// get_verification_queue().
class VerificationItem {
  final String id;
  final String date;
  final String? description;
  final String? merchantName;
  final double amount;
  final String currency;
  final String semaphore;
  final String? categoryName;
  final bool auto;
  final String? source;
  final String? matchedTo;

  VerificationItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        date = (j['transaction_date'] as String?) ?? '',
        description = j['description'] as String?,
        merchantName = j['merchant_name'] as String?,
        amount = (j['amount'] as num?)?.toDouble() ?? 0,
        currency = (j['currency'] as String?) ?? 'USD',
        semaphore = (j['semaphore'] as String?) ?? 'green',
        categoryName = j['category_account_name'] as String?,
        auto = (j['auto'] as bool?) ?? false,
        source = j['source'] as String?,
        matchedTo = j['matched_to'] as String?;

  String get title => merchantName ?? description ?? 'Transaction';
}

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
  /// Every leaf account of this scope except the bank/cash accounts (the bank
  /// side is implied) -- the set post_reviewed_transactions accepts, same as
  /// the web. Not only income/expense: an owner's contribution is equity, a
  /// loan payment a liability, equipment an asset.
  Future<List<CategoryAccount>> getCategories(String orgId, String? clientId) async {
    var q = _db
        .from('accounts')
        .select('id, code, name, type, parent_id, cash_flow_category')
        .eq('org_id', orgId)
        .eq('is_active', true);
    q = clientId != null ? q.eq('client_id', clientId) : q.isFilter('client_id', null);
    final rows = (await q.order('code')).cast<Map<String, dynamic>>();
    final parents = rows.map((r) => r['parent_id']).whereType<String>().toSet();
    return rows
        .where((r) => !parents.contains(r['id']) && !_isCash(r))
        .map((r) => CategoryAccount(
              id: r['id'] as String,
              code: (r['code'] as String?) ?? '',
              name: (r['name'] as String?) ?? '',
              type: r['type'] as String,
            ))
        .toList();
  }

  static bool _isCash(Map<String, dynamic> r) {
    final name = ((r['name'] as String?) ?? '').toLowerCase();
    return r['type'] == 'asset' &&
        (r['cash_flow_category'] == 'cash' || RegExp(r'(checking|cash|bank)').hasMatch(name)) &&
        !RegExp(r'(undeposited|in transit)').hasMatch(name);
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

  // ── Verify: green (ready) -> blue (verified) ──────────────────────────────

  Future<List<VerificationItem>> getVerificationQueue(String orgId, String? clientId) async {
    final data = await _db.rpc('get_verification_queue', params: {
      'p_org_id': orgId,
      'p_client_id': clientId,
    });
    return (((data as Map)['items'] as List?) ?? [])
        .map((e) => VerificationItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Throws a StateError with the database's reason when it refuses one
  /// (for example LV005: not categorized yet).
  Future<void> verify(String orgId, String transactionId) async {
    final data = await _db.rpc('verify_transactions', params: {
      'p_org_id': orgId,
      'p_transaction_ids': [transactionId],
    });
    final failed = ((data as Map?)?['failed'] as List?) ?? const [];
    if (failed.isNotEmpty) {
      final f = Map<String, dynamic>.from(failed.first as Map);
      throw StateError((f['error'] as String?) ?? 'Could not verify this transaction.');
    }
  }

  /// Takes the category off: back to For review, and the merchant goes back
  /// to "ask me".
  Future<void> uncategorize(String orgId, String transactionId) async {
    await _db.rpc('uncategorize_transaction', params: {
      'p_org_id': orgId,
      'p_transaction_id': transactionId,
    });
  }
}
