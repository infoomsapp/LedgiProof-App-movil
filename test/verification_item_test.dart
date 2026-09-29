import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/review_service.dart';

void main() {
  test('reads a get_verification_queue row', () {
    final it = VerificationItem.fromJson({
      'id': 'tx-1',
      'transaction_date': '2026-09-07',
      'merchant_name': 'Starbucks',
      'amount': -8,
      'currency': 'USD',
      'semaphore': 'green',
      'category_account_name': 'Meals',
      'auto': true,
      'source': 'learned',
      'matched_to': null,
    });
    expect(it.title, 'Starbucks');
    expect(it.amount, -8);
    expect(it.auto, isTrue);
    expect(it.categoryName, 'Meals');
    expect(suggestionSourceLabel(it.source), 'Learned');
  });

  test('the bank category seed has a label', () {
    expect(suggestionSourceLabel('bank_category'), "Bank's category");
  });
}
