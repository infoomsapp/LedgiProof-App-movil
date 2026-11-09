// The dashboard's three numbers and colour bar come from
// get_transaction_summary; what the phone does with its answer is worth pinning.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/transactions_service.dart';

void main() {
  test('counts per colour, money in, money out, needs review', () {
    final r = TransactionsService.summaryFromJson({
      'counts': {'blue': 2, 'green': 2, 'amber': 2, 'red': 1},
      'money_in': 4450.00,
      'money_out': 12526.45,
    });
    expect(r.counts, {'blue': 2, 'green': 2, 'amber': 2, 'red': 1, 'all': 7});
    expect(r.totals.moneyIn, 4450.00);
    expect(r.totals.moneyOut, closeTo(12526.45, 0.001));
    expect(r.totals.needsReview, 3); // amber + red
  });

  test('an unknown colour is not counted as one of the four', () {
    final r = TransactionsService.summaryFromJson({
      'counts': {'purple': 1},
      'money_in': 5.0,
      'money_out': 5.0,
    });
    expect(r.counts['all'], 0);
    expect(r.totals.moneyIn, 5.0); // money still adds up
  });

  test('empty period', () {
    final r = TransactionsService.summaryFromJson({'counts': {}, 'money_in': 0, 'money_out': 0});
    expect(r.counts['all'], 0);
    expect(r.totals.needsReview, 0);
    expect(r.totals.moneyIn, 0);
  });

  test('periods start where they say', () {
    final now = DateTime(2026, 9, 25, 15, 30);
    expect(TxPeriod.days30.since(now), DateTime(2026, 8, 26));
    expect(TxPeriod.days90.since(now), DateTime(2026, 6, 27));
    expect(TxPeriod.thisYear.since(now), DateTime(2026, 1, 1));
    expect(TxPeriod.all.since(now), isNull);
  });
}
