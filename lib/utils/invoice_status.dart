/// How an invoice reads to a person, derived from what the server stored.
///
/// The stored status only flips to 'overdue' when something writes it, so the
/// phone works it out from the due date the moment an invoice is late -- the
/// same way QuickBooks shows "N days overdue" under the customer's name. Kept
/// free of Flutter so the rules can be tested on their own.
library;

enum InvoiceBucket { draft, awaiting, overdue, paid, voided }

class InvoiceStanding {
  final InvoiceBucket bucket;

  /// Some money has been paid but not all of it.
  final bool partial;

  /// Whole days past the due date (0 unless overdue).
  final int daysOverdue;

  /// Whole days until the due date (0 unless awaiting; 0 also means due today).
  final int daysUntilDue;

  /// One short line for a list row: "Overdue · 12 days", "Due in 5 days"...
  final String label;

  const InvoiceStanding(
    this.bucket,
    this.label, {
    this.partial = false,
    this.daysOverdue = 0,
    this.daysUntilDue = 0,
  });
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// [status] is the stored invoice_status (draft, sent, viewed, partial, paid,
/// overdue, void). Money is compared, not just the status, because a balance
/// of zero means paid whatever the status column says.
InvoiceStanding invoiceStanding({
  required String status,
  required double total,
  required double balanceDue,
  required DateTime? dueDate,
  DateTime? now,
}) {
  if (status == 'void') {
    return const InvoiceStanding(InvoiceBucket.voided, 'Void');
  }
  if (status == 'draft') {
    return const InvoiceStanding(InvoiceBucket.draft, 'Draft');
  }
  if (status == 'paid' || balanceDue <= 0) {
    return const InvoiceStanding(InvoiceBucket.paid, 'Paid');
  }

  final partial = status == 'partial' || (balanceDue < total && balanceDue > 0);
  final today = _dateOnly(now ?? DateTime.now());

  if (dueDate != null) {
    final due = _dateOnly(dueDate);
    final diff = due.difference(today).inDays;
    if (diff < 0) {
      final late = -diff;
      return InvoiceStanding(
        InvoiceBucket.overdue,
        'Overdue · ${_plural(late, 'day')}',
        partial: partial,
        daysOverdue: late,
      );
    }
    final label = diff == 0
        ? 'Due today'
        : diff == 1
            ? 'Due tomorrow'
            : 'Due in ${_plural(diff, 'day')}';
    return InvoiceStanding(
      InvoiceBucket.awaiting,
      partial ? 'Partly paid · $label' : label,
      partial: partial,
      daysUntilDue: diff,
    );
  }
  return InvoiceStanding(
    InvoiceBucket.awaiting,
    partial ? 'Partly paid' : 'Awaiting payment',
    partial: partial,
  );
}

/// The two numbers at the top of the invoice list.
class InvoiceTotals {
  final double outstanding;
  final double overdue;
  final int overdueCount;
  const InvoiceTotals(this.outstanding, this.overdue, this.overdueCount);
}

/// [rows] are (standing, balanceDue) pairs; drafts, paid and void invoices do
/// not count as money owed to you.
InvoiceTotals summarizeInvoices(
    Iterable<({InvoiceStanding standing, double balanceDue})> rows) {
  var outstanding = 0.0;
  var overdue = 0.0;
  var overdueCount = 0;
  for (final r in rows) {
    switch (r.standing.bucket) {
      case InvoiceBucket.awaiting:
        outstanding += r.balanceDue;
      case InvoiceBucket.overdue:
        outstanding += r.balanceDue;
        overdue += r.balanceDue;
        overdueCount++;
      case InvoiceBucket.draft:
      case InvoiceBucket.paid:
      case InvoiceBucket.voided:
        break;
    }
  }
  return InvoiceTotals(outstanding, overdue, overdueCount);
}

/// Payment terms offered when composing: due on receipt, Net 7/15/30/60.
enum DueTerms { onReceipt, net7, net15, net30, net60 }

extension DueTermsInfo on DueTerms {
  String get label => switch (this) {
        DueTerms.onReceipt => 'On receipt',
        DueTerms.net7 => 'Net 7',
        DueTerms.net15 => 'Net 15',
        DueTerms.net30 => 'Net 30',
        DueTerms.net60 => 'Net 60',
      };

  int get days => switch (this) {
        DueTerms.onReceipt => 0,
        DueTerms.net7 => 7,
        DueTerms.net15 => 15,
        DueTerms.net30 => 30,
        DueTerms.net60 => 60,
      };

  DateTime dueFrom(DateTime issue) =>
      _dateOnly(issue).add(Duration(days: days));
}
