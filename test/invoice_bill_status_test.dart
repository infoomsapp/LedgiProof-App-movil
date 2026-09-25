// An invoice / bill has to read the way an accountant expects the moment it is
// late, without waiting for anything to rewrite a stored status.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/utils/bill_status.dart';
import 'package:ledgiproof/utils/invoice_status.dart';

final today = DateTime(2026, 9, 25, 14, 30); // time of day must not matter

InvoiceStanding st(String status, double total, double balance, DateTime? due) =>
    invoiceStanding(
      status: status,
      total: total,
      balanceDue: balance,
      dueDate: due,
      now: today,
    );

void main() {
  group('invoiceStanding', () {
    test('draft and void never look like money owed', () {
      expect(st('draft', 100, 100, DateTime(2026, 1, 1)).bucket, InvoiceBucket.draft);
      expect(st('void', 100, 100, DateTime(2026, 1, 1)).bucket, InvoiceBucket.voided);
    });

    test('a zero balance is paid whatever the status column says', () {
      expect(st('sent', 100, 0, DateTime(2026, 1, 1)).bucket, InvoiceBucket.paid);
      expect(st('paid', 100, 100, null).bucket, InvoiceBucket.paid);
    });

    test('past the due date it is overdue, counted in whole days', () {
      final s = st('sent', 100, 100, DateTime(2026, 9, 13));
      expect(s.bucket, InvoiceBucket.overdue);
      expect(s.daysOverdue, 12);
      expect(s.label, 'Overdue · 12 days');
      expect(st('sent', 100, 100, DateTime(2026, 9, 24)).label, 'Overdue · 1 day');
    });

    test('due today is not overdue, whatever the time of day', () {
      final s = st('sent', 100, 100, DateTime(2026, 9, 25));
      expect(s.bucket, InvoiceBucket.awaiting);
      expect(s.label, 'Due today');
    });

    test('future due dates read as days until due', () {
      expect(st('viewed', 100, 100, DateTime(2026, 9, 26)).label, 'Due tomorrow');
      final s = st('sent', 100, 100, DateTime(2026, 9, 30));
      expect(s.label, 'Due in 5 days');
      expect(s.daysUntilDue, 5);
    });

    test('partial payments are flagged but keep their bucket', () {
      final a = st('partial', 100, 40, DateTime(2026, 10, 10));
      expect(a.partial, isTrue);
      expect(a.bucket, InvoiceBucket.awaiting);
      expect(a.label, startsWith('Partly paid'));
      final o = st('partial', 100, 40, DateTime(2026, 9, 1));
      expect(o.bucket, InvoiceBucket.overdue);
      expect(o.partial, isTrue);
    });

    test('no due date at all', () {
      expect(st('sent', 100, 100, null).label, 'Awaiting payment');
    });
  });

  group('summarizeInvoices', () {
    test('only awaiting and overdue balances count as owed', () {
      final rows = [
        (standing: st('sent', 100, 100, DateTime(2026, 10, 1)), balanceDue: 100.0),
        (standing: st('sent', 200, 200, DateTime(2026, 9, 1)), balanceDue: 200.0),
        (standing: st('partial', 300, 50, DateTime(2026, 9, 10)), balanceDue: 50.0),
        (standing: st('draft', 999, 999, null), balanceDue: 999.0),
        (standing: st('paid', 400, 0, null), balanceDue: 0.0),
        (standing: st('void', 500, 500, null), balanceDue: 500.0),
      ];
      final t = summarizeInvoices(rows);
      expect(t.outstanding, 350);
      expect(t.overdue, 250);
      expect(t.overdueCount, 2);
    });
  });

  group('DueTerms', () {
    test('net terms count from the issue date, ignoring time of day', () {
      expect(DueTerms.net30.dueFrom(today), DateTime(2026, 10, 25));
      expect(DueTerms.onReceipt.dueFrom(today), DateTime(2026, 9, 25));
      expect(DueTerms.net15.dueFrom(DateTime(2026, 12, 20)), DateTime(2027, 1, 4));
    });
  });

  group('bills', () {
    BillUrgency u(String status, DateTime due) =>
        billUrgency(status: status, dueDate: due, now: today);

    test('overdue, due soon, upcoming, paid', () {
      expect(u('pending', DateTime(2026, 9, 24)), BillUrgency.overdue);
      expect(u('pending', DateTime(2026, 9, 25)), BillUrgency.dueSoon);
      expect(u('pending', DateTime(2026, 10, 2)), BillUrgency.dueSoon);
      expect(u('pending', DateTime(2026, 10, 3)), BillUrgency.upcoming);
      expect(u('paid', DateTime(2026, 1, 1)), BillUrgency.paid);
      // the stored 'overdue' status is not needed to read as overdue
      expect(u('pending', DateTime(2026, 9, 1)), BillUrgency.overdue);
    });

    test('labels', () {
      String l(DateTime d) =>
          billDueLabel(status: 'pending', dueDate: d, now: today);
      expect(l(DateTime(2026, 9, 13)), '12 days overdue');
      expect(l(DateTime(2026, 9, 24)), '1 day overdue');
      expect(l(DateTime(2026, 9, 25)), 'Due today');
      expect(l(DateTime(2026, 9, 26)), 'Due tomorrow');
      expect(l(DateTime(2026, 9, 30)), 'Due in 5 days');
      expect(billDueLabel(status: 'paid', dueDate: DateTime(2026, 1, 1), now: today), 'Paid');
    });

    test('summary ignores paid bills', () {
      final t = summarizeBills([
        (status: 'pending', dueDate: DateTime(2026, 9, 1), amount: 100.0),
        (status: 'pending', dueDate: DateTime(2026, 9, 28), amount: 50.0),
        (status: 'pending', dueDate: DateTime(2026, 12, 1), amount: 25.0),
        (status: 'paid', dueDate: DateTime(2026, 9, 1), amount: 999.0),
      ], now: today);
      expect(t.toPay, 175);
      expect(t.overdue, 100);
      expect(t.dueSoon, 50);
    });
  });
}
