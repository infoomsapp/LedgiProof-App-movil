// The dashboard's three numbers and colour bar are computed on the phone from
// the rows of the chosen period, so the arithmetic is worth pinning.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/transactions_service.dart';

void main() {
  test('counts per colour, money in, money out, needs review', () {
    final r = TransactionsService.summarize([
      (semaphore: 'blue', amount: 1250.00),
      (semaphore: 'blue', amount: 3200.00),
      (semaphore: 'green', amount: -6.45),
      (semaphore: 'green', amount: -1800.00),
      (semaphore: 'amber', amount: -320.00),
      (semaphore: 'amber', amount: -900.00),
      (semaphore: 'red', amount: -9500.00),
    ]);
    expect(r.counts, {'blue': 2, 'green': 2, 'amber': 2, 'red': 1, 'all': 7});
    expect(r.totals.moneyIn, 4450.00);
    expect(r.totals.moneyOut, closeTo(12526.45, 0.001));
    expect(r.totals.needsReview, 3); // amber + red
  });

  test('an unknown colour is not counted as one of the four', () {
    final r = TransactionsService.summarize([
      (semaphore: 'purple', amount: -5.0),
      (semaphore: null, amount: 5.0),
    ]);
    expect(r.counts['all'], 0);
    expect(r.totals.moneyIn, 5.0); // money still adds up
  });

  test('empty period', () {
    final r = TransactionsService.summarize([]);
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
