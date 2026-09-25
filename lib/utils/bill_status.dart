/// How a vendor bill reads to a person. Same idea as invoice_status.dart: the
/// stored status only becomes 'overdue' when something writes it, so the phone
/// derives it from the due date the moment a bill is late.
library;

enum BillUrgency { overdue, dueSoon, upcoming, paid }

/// A bill due within this many days shows as "due soon" (matches the web's
/// billUrgency).
const billDueSoonDays = 7;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

BillUrgency billUrgency({
  required String status,
  required DateTime dueDate,
  DateTime? now,
}) {
  if (status == 'paid') return BillUrgency.paid;
  final today = _dateOnly(now ?? DateTime.now());
  final days = _dateOnly(dueDate).difference(today).inDays;
  if (days < 0) return BillUrgency.overdue;
  if (days <= billDueSoonDays) return BillUrgency.dueSoon;
  return BillUrgency.upcoming;
}

/// "Due in 5 days", "Due today", "12 days overdue", "Paid".
String billDueLabel({
  required String status,
  required DateTime dueDate,
  DateTime? now,
}) {
  if (status == 'paid') return 'Paid';
  final today = _dateOnly(now ?? DateTime.now());
  final days = _dateOnly(dueDate).difference(today).inDays;
  String plural(int n) => '$n day${n == 1 ? '' : 's'}';
  if (days < 0) return '${plural(-days)} overdue';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in ${plural(days)}';
}

class BillTotals {
  final double toPay;
  final double overdue;
  final double dueSoon;
  const BillTotals(this.toPay, this.overdue, this.dueSoon);
}

/// [rows] are (status, dueDate, amount). Paid bills are not money still owed.
BillTotals summarizeBills(
  Iterable<({String status, DateTime dueDate, double amount})> rows, {
  DateTime? now,
}) {
  var toPay = 0.0, overdue = 0.0, dueSoon = 0.0;
  for (final r in rows) {
    switch (billUrgency(status: r.status, dueDate: r.dueDate, now: now)) {
      case BillUrgency.paid:
        break;
      case BillUrgency.overdue:
        toPay += r.amount;
        overdue += r.amount;
      case BillUrgency.dueSoon:
        toPay += r.amount;
        dueSoon += r.amount;
      case BillUrgency.upcoming:
        toPay += r.amount;
    }
  }
  return BillTotals(toPay, overdue, dueSoon);
}
