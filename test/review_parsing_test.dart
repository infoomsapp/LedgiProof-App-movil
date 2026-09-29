import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/receipt_service.dart';
import 'package:ledgiproof/services/review_service.dart';

// Shapes copied from what get_review_queue(), post_reviewed_transactions()
// and ocr-receipt (match_receipt) return on the live database.
void main() {
  group('review queue', () {
    test('parses items, suggestion and receipt flag', () {
      final q = ReviewQueue.fromJson({
        'items': [
          {
            'id': 't1',
            'transaction_date': '2026-09-20',
            'description': 'POS DEBIT ACME WIDGETS 123',
            'merchant_name': null,
            'amount': -30,
            'currency': 'USD',
            'semaphore': 'green',
            'status_reason': null,
            'suggested_account_id': 'a1',
            'suggestion_source': 'learned',
            'suggestion_confidence': 86,
            'has_receipt': true,
          },
          {
            'id': 't2',
            'transaction_date': '2026-09-21',
            'description': 'DEPOSIT STRIPE PAYOUT',
            'amount': 500.0,
            'currency': 'USD',
            'semaphore': 'red',
          },
        ],
        'total': 7,
        'bank_account': 'b1',
      });
      expect(q.total, 7);
      expect(q.hasBankAccount, isTrue);
      expect(q.items.first.amount, -30.0);
      expect(q.items.first.moneyIn, isFalse);
      expect(q.items.first.hasReceipt, isTrue);
      expect(q.items.first.label, 'POS DEBIT ACME WIDGETS 123');
      expect(q.items.first.suggestionConfidence, 86);
      expect(q.items.last.moneyIn, isTrue);
      expect(q.items.last.suggestedAccountId, isNull);
      expect(q.items.last.hasReceipt, isFalse);
    });

    test('no bank account in the chart', () {
      final q = ReviewQueue.fromJson({'items': [], 'total': 0, 'bank_account': null});
      expect(q.hasBankAccount, isFalse);
      expect(q.items, isEmpty);
    });
  });

  test('deposit matches: an open invoice, or a recorded payment', () {
    final q = ReviewQueue.fromJson({
      'items': [
        {
          'id': 't1', 'transaction_date': '2026-09-27', 'description': 'ZELLE FROM ZENITH LABS',
          'amount': 200, 'currency': 'USD', 'semaphore': 'green',
          'suggested_account_id': 'ar', 'suggestion_source': 'invoice', 'suggestion_confidence': 95,
          'invoice_match': {'invoice_id': 'i2', 'invoice_number': 'T-002', 'client_name': 'Zenith Labs', 'balance_due': 200},
          'deposit_match': null,
        },
        {
          'id': 't2', 'transaction_date': '2026-09-27', 'description': 'MOBILE DEPOSIT',
          'amount': 65, 'currency': 'USD', 'semaphore': 'green',
          'suggested_account_id': 'und', 'suggestion_source': 'deposit', 'suggestion_confidence': 95,
          'invoice_match': null,
          'deposit_match': {'payment_id': 'p1', 'invoice_number': 'T-001', 'payment_date': '2026-09-27', 'method': 'check'},
        },
      ],
      'total': 2,
      'bank_account': 'b1',
    });
    final inv = q.items[0].match!;
    expect(inv.invoiceId, 'i2');
    expect(inv.paymentId, isNull);
    expect(inv.label, 'Payment for T-002 · Zenith Labs');
    final dep = q.items[1].match!;
    expect(dep.paymentId, 'p1');
    expect(dep.invoiceId, isNull);
    expect(dep.label, 'Deposit of the payment on T-001');
    expect(suggestionSourceLabel('invoice'), 'Invoice payment');
  });

  test('post result: posted, per-row failures and the rule prompt', () {
    final r = PostResult.fromJson({
      'posted': ['t3'],
      'failed': [
        {'transaction_id': 't2', 'error': 'Choose a specific account, not a group heading'},
      ],
      'rule_prompts': [
        {
          'merchant_key': 'acme widgets',
          'client_id': 'c1',
          'account_id': 'a1',
          'account_name': 'Medical Supplies',
          'example': 'ACME WIDGETS #555',
        },
      ],
    });
    expect(r.posted, {'t3'});
    expect(r.failed['t2'], contains('group heading'));
    expect(r.rulePrompts.single.merchantKey, 'acme widgets');
    expect(r.rulePrompts.single.clientId, 'c1');
  });

  test('source labels match the web', () {
    expect(suggestionSourceLabel('merchant'), 'Known merchant');
    // No AI in categorization: an 'ai' source is not a thing any more.
    expect(suggestionSourceLabel('ai'), '');
    expect(suggestionSourceLabel(null), '');
  });

  group('receipt match', () {
    Map<String, dynamic> ocr(Map<String, dynamic>? match) => {
          'document_id': 'd1',
          'match': match,
          'merchant_name': 'The Home Depot',
          'total_amount': 42.17,
          'date': '2026-09-19',
          'currency': 'USD',
          'confidence': 92,
        };

    test('matched', () {
      final r = OcrResult.fromJson(ocr({
        'status': 'matched',
        'transaction': {'id': 't1', 'description': 'HOME DEPOT', 'amount': -42.17, 'transaction_date': '2026-09-20'},
      }));
      expect(r.documentId, 'd1');
      expect(r.match!.status, 'matched');
      expect(r.match!.transaction!.amount, -42.17);
    });

    test('suggested candidates', () {
      final r = OcrResult.fromJson(ocr({
        'status': 'suggested',
        'candidates': [
          {'id': 't2', 'description': 'CAFE ONE', 'amount': -10, 'transaction_date': '2026-09-20', 'score': 85},
          {'id': 't3', 'description': 'CAFE TWO', 'amount': -10, 'transaction_date': '2026-09-20', 'score': 85},
        ],
      }));
      expect(r.match!.candidates.map((c) => c.id), ['t2', 't3']);
      expect(r.match!.transaction, isNull);
    });

    test('waiting, and a server that could not match', () {
      expect(OcrResult.fromJson(ocr({'status': 'unmatched'})).match!.status, 'unmatched');
      expect(OcrResult.fromJson(ocr(null)).match, isNull);
    });
  });

  // Shape of get_pending_receipts() on the live database.
  group('pending receipts', () {
    test('parses OCR fields and candidates', () {
      final r = PendingReceipt.fromJson({
        'id': 'd1',
        'filename': 'IMG_0001.jpg',
        'created_at': '2026-09-28T13:00:00Z',
        'match_status': 'suggested',
        'ocr_merchant': 'Shell',
        'ocr_amount': 24.5,
        'ocr_date': '2026-09-21',
        'ocr_currency': 'usd',
        'ocr_confidence': 88,
        'candidates': [
          {'id': 't1', 'description': 'SHELL OIL 5739', 'amount': -24.50, 'transaction_date': '2026-09-21', 'score': 80},
        ],
      });
      expect(r.label, 'Shell');
      expect(r.amount, 24.5);
      expect(r.currency, 'USD');
      expect(r.candidates.single.id, 't1');
      expect(formatMoney(r.candidates.single.amount, r.currency), '\$24.50');
    });

    test('a receipt nothing could read falls back to its filename', () {
      final r = PendingReceipt.fromJson({
        'id': 'd2',
        'filename': 'IMG_0002.jpg',
        'match_status': 'no_amount',
        'ocr_merchant': null,
        'ocr_amount': null,
        'ocr_date': null,
        'ocr_currency': null,
        'candidates': [],
      });
      expect(r.label, 'IMG_0002.jpg');
      expect(r.amount, isNull);
      expect(r.matchStatus, 'no_amount');
      expect(formatMoney(12, 'EUR'), 'EUR 12.00');
    });
  });
}
