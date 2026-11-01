import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/report_service.dart';
import 'package:ledgiproof/utils/report_period.dart';

void main() {
  group('report period', () {
    test('a month, a quarter and a year span the right days', () {
      const m = ReportPeriod(PeriodKind.month, 2026, 2);
      expect(isoDay(m.from), '2026-02-01');
      expect(isoDay(m.to), '2026-02-28');
      expect(m.label, 'February 2026');
      expect(m.months, 1);

      const q = ReportPeriod(PeriodKind.quarter, 2026, 8);
      expect(q.quarter, 3);
      expect(isoDay(q.from), '2026-07-01');
      expect(isoDay(q.to), '2026-09-30');
      expect(q.label, 'Q3 2026');
      expect(q.span, 'Jul 1 – Sep 30, 2026');
      expect(q.endLabel, 'Sep 30, 2026');
      expect(q.months, 3);

      const y = ReportPeriod(PeriodKind.year, 2024, 5);
      expect(isoDay(y.from), '2024-01-01');
      expect(isoDay(y.to), '2024-12-31');
      expect(y.label, '2024');
      expect(y.lastMonth, 12);
      expect(y.months, 12);
    });

    test('the arrows step one period and cross the year', () {
      const jan = ReportPeriod(PeriodKind.month, 2026, 1);
      expect(jan.step(-1).label, 'December 2025');
      expect(const ReportPeriod(PeriodKind.month, 2026, 12).step(1).label, 'January 2027');
      const q1 = ReportPeriod(PeriodKind.quarter, 2026, 2);
      expect(q1.step(-1).label, 'Q4 2025');
      expect(q1.step(1).label, 'Q2 2026');
      expect(const ReportPeriod(PeriodKind.year, 2026, 11).step(-1).label, '2025');
    });

    test('switching kind keeps the month you were on', () {
      const nov = ReportPeriod(PeriodKind.month, 2026, 11);
      expect(nov.withKind(PeriodKind.quarter).label, 'Q4 2026');
      expect(nov.withKind(PeriodKind.year).withKind(PeriodKind.month).label, 'November 2026');
      expect(nov.withKind(PeriodKind.quarter)
          .sameAs(const ReportPeriod(PeriodKind.quarter, 2026, 10)), isTrue);
      expect(nov.sameAs(const ReportPeriod(PeriodKind.month, 2026, 10)), isFalse);
    });

    test('a leap February ends on the 29th', () {
      expect(isoDay(const ReportPeriod(PeriodKind.month, 2028, 2).to), '2028-02-29');
      expect(ReportPeriod.thisMonth(DateTime(2026, 11, 1)).label, 'November 2026');
    });
  });

  // Shape of get_budget_vs_actual_range() on the live database.
  test('budget over a quarter says how many months have a budget', () {
    final b = BudgetVsActual.fromJson({
      'period': '2026-07 to 2026-09',
      'months': 3,
      'budgeted_months': 2,
      'total_budget': 500,
      'total_actual': 227.71,
      'period_budget': 1000,
      'lines': [],
    });
    expect(b.months, 3);
    expect(b.budgetedMonths, 2);
    expect(b.ceilingLeft, closeTo(772.29, 0.001));
    // An older server without the counts reads as one month.
    final old = BudgetVsActual.fromJson({'period': '2026-07', 'lines': []});
    expect(old.months, 1);
    expect(old.budgetedMonths, 0);
  });
}
