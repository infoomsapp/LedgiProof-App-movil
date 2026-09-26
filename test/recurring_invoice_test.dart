// The recurring-invoice list and the reminder policy are what a bookkeeper
// reads to know what will be billed and emailed without them lifting a finger.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/recurring_invoice_service.dart';

Map<String, dynamic> row({
  String status = 'active',
  String frequency = 'monthly',
  int generated = 0,
  int? max,
  bool auto = false,
  List<Map<String, dynamic>>? items,
  Object? clients = const {'display_name': 'Ana', 'company_name': 'Perez Design LLC'},
}) =>
    {
      'id': 'r1',
      'client_id': 'c1',
      'title': 'Monthly bookkeeping',
      'currency': 'USD',
      'frequency': frequency,
      'next_run_date': '2026-10-01',
      'end_date': null,
      'max_occurrences': max,
      'occurrences_generated': generated,
      'net_days': 30,
      'auto_send': auto,
      'status': status,
      'clients': clients,
      'recurring_invoice_items': items ??
          [
            {'quantity': 1, 'unit_price': 1000, 'discount_pct': 0, 'tax_rate': 0},
            {'quantity': 2, 'unit_price': 100, 'discount_pct': 0, 'tax_rate': 0},
          ],
    };

void main() {
  group('RecurringInvoice', () {
    test('reads a row and previews what one invoice will total', () {
      final r = RecurringInvoice.fromRow(row());
      expect(r.clientName, 'Perez Design LLC'); // company wins, like the list
      expect(r.frequency, RecurringFrequency.monthly);
      expect(r.amount, 1200);
      expect(r.autoSend, isFalse);
      expect(r.netDays, 30);
    });

    test('preview applies discount then tax per line, rounded to cents', () {
      final r = RecurringInvoice.fromRow(row(items: [
        {'quantity': 2, 'unit_price': 100, 'discount_pct': 10, 'tax_rate': 8.25},
      ]));
      expect(r.amount, 194.85); // 200 * 0.9 * 1.0825
    });

    test('a schedule with no lines previews zero, not a crash', () {
      expect(RecurringInvoice.fromRow(row(items: [])).amount, 0);
      final bare = row()..remove('recurring_invoice_items');
      expect(RecurringInvoice.fromRow(bare).amount, 0);
    });

    test('client can be missing', () {
      expect(RecurringInvoice.fromRow(row(clients: null)).clientName, isNull);
    });

    test('schedule line says when it runs, or why it does not', () {
      expect(RecurringInvoice.fromRow(row()).scheduleLine, 'Monthly · next Oct 1, 2026');
      expect(RecurringInvoice.fromRow(row(status: 'paused', frequency: 'biweekly')).scheduleLine,
          'Every 2 weeks · paused');
      expect(RecurringInvoice.fromRow(row(status: 'ended', frequency: 'yearly')).scheduleLine,
          'Yearly · ended');
    });

    test('progress', () {
      expect(RecurringInvoice.fromRow(row()).progress, '');
      expect(RecurringInvoice.fromRow(row(generated: 3)).progress, '3 created');
      expect(RecurringInvoice.fromRow(row(generated: 3, max: 12)).progress, '3 of 12 created');
    });

    test('unknown values fall back safely', () {
      final r = RecurringInvoice.fromRow(row(status: 'weird', frequency: 'hourly'));
      expect(r.status, RecurringStatus.active);
      expect(r.frequency, RecurringFrequency.monthly);
    });
  });

  group('ReminderPolicy', () {
    test('defaults are off, with sensible milestones', () {
      const p = ReminderPolicy();
      expect(p.enabled, isFalse);
      expect(p.daysBefore, 3);
      expect(p.onDue, isTrue);
      expect(p.overdueDays, [3, 7, 14]);
    });

    test('reads a row', () {
      final p = ReminderPolicy.fromRow({
        'enabled': true,
        'days_before': 5,
        'on_due': false,
        'overdue_days': [14, 7, 7, 200, 0],
      });
      expect(p.enabled, isTrue);
      expect(p.daysBefore, 5);
      expect(p.onDue, isFalse);
      expect(p.overdueDays, [7, 14]);
    });

    test('summary reads as a sentence', () {
      expect(const ReminderPolicy().summary,
          '3 days before it is due, on the due date, and 3, 7 and 14 days after.');
      expect(const ReminderPolicy(daysBefore: 1, onDue: false, overdueDays: [7]).summary,
          '1 day before it is due, and 7 days after.');
      expect(const ReminderPolicy(daysBefore: 0, onDue: true, overdueDays: []).summary,
          'On the due date.');
      expect(const ReminderPolicy(daysBefore: 0, onDue: false, overdueDays: []).summary,
          'No reminders selected.');
    });

    test('copyWith changes only what it is given', () {
      final p = const ReminderPolicy().copyWith(enabled: true, daysBefore: 7);
      expect(p.enabled, isTrue);
      expect(p.daysBefore, 7);
      expect(p.onDue, isTrue);
      expect(p.overdueDays, [3, 7, 14]);
    });
  });

  test('overdue days match what the database accepts: unique, sorted, 1-90, max 6', () {
    expect(normalizeOverdueDays([14, 3, 7, 3]), [3, 7, 14]);
    expect(normalizeOverdueDays([0, -2, 91, 5]), [5]);
    expect(normalizeOverdueDays([1, 2, 3, 4, 5, 6, 7, 8]), [1, 2, 3, 4, 5, 6]);
    expect(normalizeOverdueDays([]), isEmpty);
  });
}
