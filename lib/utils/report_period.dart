/// The period a report covers: a month, a quarter or a year.
///
/// It is kept as one anchor month plus a kind, so switching Month -> Quarter
/// -> Year and back lands on the period that contains the month you were
/// looking at, instead of jumping back to today.
enum PeriodKind { month, quarter, year }

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class ReportPeriod {
  final PeriodKind kind;
  final int year;

  /// 1-12. For a quarter or a year, any month inside it.
  final int month;

  const ReportPeriod(this.kind, this.year, this.month);

  factory ReportPeriod.thisMonth([DateTime? today]) {
    final t = today ?? DateTime.now();
    return ReportPeriod(PeriodKind.month, t.year, t.month);
  }

  /// 1-4.
  int get quarter => (month - 1) ~/ 3 + 1;

  int get firstMonth => switch (kind) {
        PeriodKind.month => month,
        PeriodKind.quarter => (quarter - 1) * 3 + 1,
        PeriodKind.year => 1,
      };

  int get lastMonth => switch (kind) {
        PeriodKind.month => month,
        PeriodKind.quarter => quarter * 3,
        PeriodKind.year => 12,
      };

  DateTime get from => DateTime(year, firstMonth, 1);

  /// The last day of the period (day 0 of the next month).
  DateTime get to => DateTime(year, lastMonth + 1, 0);

  int get months => lastMonth - firstMonth + 1;

  ReportPeriod withKind(PeriodKind k) => ReportPeriod(k, year, month);

  /// The period before (-1) or after (+1), of the same kind.
  ReportPeriod step(int direction) {
    final by = switch (kind) {
      PeriodKind.month => 1,
      PeriodKind.quarter => 3,
      PeriodKind.year => 12,
    };
    final index = year * 12 + (month - 1) + direction * by;
    return ReportPeriod(kind, index ~/ 12, index % 12 + 1);
  }

  /// Whether [other] is the same period, e.g. any month of Q3 is the same
  /// quarter.
  bool sameAs(ReportPeriod other) =>
      kind == other.kind && year == other.year && firstMonth == other.firstMonth;

  /// "October 2026", "Q4 2026", "2026".
  String get label => switch (kind) {
        PeriodKind.month => '${monthNames[month - 1]} $year',
        PeriodKind.quarter => 'Q$quarter $year',
        PeriodKind.year => '$year',
      };

  /// "Oct 1 – Dec 31, 2026" -- what a quarter or a year actually spans.
  String get span {
    String d(DateTime x) => '${monthNames[x.month - 1].substring(0, 3)} ${x.day}';
    return '${d(from)} – ${d(to)}, $year';
  }

  /// "Sep 30, 2026": the date a balance sheet for this period is as of.
  String get endLabel =>
      '${monthNames[lastMonth - 1].substring(0, 3)} ${to.day}, $year';
}

/// YYYY-MM-DD, local date (never shifted through UTC).
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
