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
    expect(suggestionSourceLabel('ai'), 'AI');
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
}
