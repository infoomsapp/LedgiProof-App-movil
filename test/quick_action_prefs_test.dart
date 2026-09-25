// A saved Home quick-actions list must never show something the workspace
// cannot use, never be empty, and never overflow the row.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/utils/quick_action_prefs.dart';

const firm = ['scan_receipt', 'log_time', 'manual_expense', 'transactions', 'invoices', 'bills'];
const personal = ['scan_receipt', 'log_time', 'log_trip', 'manual_expense', 'transactions', 'invoices'];

void main() {
  group('defaults', () {
    test('first five available in the default order', () {
      expect(defaultQuickActions(personal),
          ['scan_receipt', 'log_time', 'log_trip', 'manual_expense', 'transactions']);
    });
    test('a firm has no trip, so invoices takes its place', () {
      expect(defaultQuickActions(firm),
          ['scan_receipt', 'log_time', 'manual_expense', 'transactions', 'invoices']);
    });
  });

  group('resolveQuickActions', () {
    test('nothing saved -> defaults', () {
      expect(resolveQuickActions(saved: null, available: firm), defaultQuickActions(firm));
    });

    test('keeps the saved order', () {
      expect(
        resolveQuickActions(saved: ['invoices', 'transactions', 'log_time'], available: firm),
        ['invoices', 'transactions', 'log_time'],
      );
    });

    test('drops what this workspace cannot use (mileage in a firm, bills for a client)', () {
      // mileage saved, then the person moved to a firm workspace
      expect(
        resolveQuickActions(saved: ['log_trip', 'transactions'], available: firm),
        ['transactions'],
      );
      // bills saved, but this workspace cannot use them
      expect(
        resolveQuickActions(saved: ['bills', 'transactions'], available: personal),
        ['transactions'],
      );
    });

    test('drops unknown ids and duplicates', () {
      expect(
        resolveQuickActions(saved: ['transactions', 'ghost', 'transactions', 'invoices'], available: firm),
        ['transactions', 'invoices'],
      );
    });

    test('caps at five', () {
      expect(
        resolveQuickActions(saved: [...firm, 'log_trip'], available: firm).length,
        maxQuickActions,
      );
    });

    test('an empty or all-invalid list falls back to the defaults, never an empty row', () {
      expect(resolveQuickActions(saved: [], available: firm), defaultQuickActions(firm));
      expect(resolveQuickActions(saved: ['ghost'], available: firm), defaultQuickActions(firm));
    });
  });

  group('editListOrder', () {
    test('chosen first in their order, then the rest by default order', () {
      expect(
        editListOrder(chosen: ['invoices', 'transactions'], available: firm),
        ['invoices', 'transactions', 'scan_receipt', 'log_time', 'manual_expense', 'bills'],
      );
    });
    test('lists every available action exactly once', () {
      final l = editListOrder(chosen: ['bills'], available: firm);
      expect(l.toSet(), firm.toSet());
      expect(l.length, firm.length);
    });
  });
}
