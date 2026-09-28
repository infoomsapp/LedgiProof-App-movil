import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/report_service.dart';

void main() {
  test('reads the get_books_snapshot shape', () {
    final s = BooksSnapshot.fromJson({
      'owed_to_you': 200, 'owed_overdue': 200, 'you_owe': 75.5, 'you_owe_overdue': 0,
      'cash': 950, 'to_review': 3,
      'month': {'from': '2026-09-01', 'to': '2026-09-30', 'income': 0, 'expenses': 125, 'profit': -125},
      'last_month': {'profit': 200},
    });
    expect(s.owedToYou, 200);
    expect(s.youOwe, 75.5);
    expect(s.cash, 950);
    expect(s.monthProfit, -125);
    expect(s.lastMonthProfit, 200);
    expect(s.toReview, 3);
  });

  test('missing fields read as zero, not a crash', () {
    final s = BooksSnapshot.fromJson({});
    expect(s.monthProfit, 0);
    expect(s.toReview, 0);
  });
}
