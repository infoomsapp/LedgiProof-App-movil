// The Checklists screen lets a person build and run checklists entirely on the
// phone, so the rules that shape what they type and what they may do are
// pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/utils/checklist_logic.dart';

void main() {
  group('who may do what', () {
    test('only owner, admin and accountant manage; a portal client never does', () {
      for (final r in ['owner', 'admin', 'accountant']) {
        expect(canManageChecklists(r, isPortalClient: false), isTrue, reason: r);
      }
      for (final r in ['approver', 'auditor', 'readonly', 'client_owner']) {
        expect(canManageChecklists(r, isPortalClient: false), isFalse, reason: r);
      }
      expect(canManageChecklists('owner', isPortalClient: true), isFalse);
    });

    test('any member may tick a task, a portal client may not', () {
      expect(canTickChecklists(isPortalClient: false), isTrue);
      expect(canTickChecklists(isPortalClient: true), isFalse);
    });
  });

  group('parseSteps', () {
    test('one step per line, blanks and list marks removed', () {
      expect(
        parseSteps('Reconcile bank\n\n - Review AR aging\n2. Post depreciation\n• Send report\n  '),
        ['Reconcile bank', 'Review AR aging', 'Post depreciation', 'Send report'],
      );
    });

    test('handles Windows line endings and trims', () {
      expect(parseSteps('  a  \r\n  b\r\n'), ['a', 'b']);
    });

    test('a number that is part of the step is kept', () {
      expect(parseSteps('2026 close\n1099 review'), ['2026 close', '1099 review']);
    });

    test('caps title length and step count', () {
      expect(parseSteps('x' * 500).single.length, maxStepTitleLength);
      final many = List.generate(300, (i) => 'step $i').join('\n');
      expect(parseSteps(many).length, maxChecklistSteps);
    });

    test('nothing usable -> empty', () {
      expect(parseSteps(' \n\t\n - \n'), isEmpty);
    });
  });

  group('progress', () {
    test('fraction and label', () {
      expect(runProgress(4, 1), 0.25);
      expect(runProgress(0, 0), 0);
      expect(runProgressLabel(5, 3), '3 of 5 done');
      expect(runProgressLabel(0, 0), 'No tasks yet');
    });
  });

  group('task due dates', () {
    final now = DateTime(2026, 9, 25, 15);
    test('a finished task or one without a date never nags', () {
      expect(taskDue(dueAt: DateTime(2026, 1, 1), done: true, now: now), TaskDue.none);
      expect(taskDue(dueAt: null, done: false, now: now), TaskDue.none);
    });
    test('overdue, today, soon, later', () {
      expect(taskDue(dueAt: DateTime(2026, 9, 24), done: false, now: now), TaskDue.overdue);
      expect(taskDue(dueAt: DateTime(2026, 9, 25), done: false, now: now), TaskDue.today);
      expect(taskDue(dueAt: DateTime(2026, 9, 28), done: false, now: now), TaskDue.soon);
      expect(taskDue(dueAt: DateTime(2026, 10, 20), done: false, now: now), TaskDue.later);
    });
    test('labels', () {
      expect(taskDueLabel(dueAt: DateTime(2026, 9, 21), now: now), 'Overdue · 4 days');
      expect(taskDueLabel(dueAt: DateTime(2026, 9, 24), now: now), 'Overdue · 1 day');
      expect(taskDueLabel(dueAt: DateTime(2026, 9, 25), now: now), 'Due today');
      expect(taskDueLabel(dueAt: DateTime(2026, 9, 26), now: now), 'Due tomorrow');
      expect(taskDueLabel(dueAt: DateTime(2026, 9, 28), now: now), 'Due in 3 days');
      expect(taskDueLabel(dueAt: DateTime(2026, 10, 3), now: now), 'Due Oct 3');
    });
  });

  group('templates', () {
    test('frequency parses the database values and labels them', () {
      expect(frequencyFrom('monthly'), ChecklistFrequency.monthly);
      expect(frequencyFrom('nope'), isNull);
      expect(ChecklistFrequency.biweekly.label, 'Every 2 weeks');
      expect(ChecklistFrequency.values.map((f) => f.value),
          ['weekly', 'biweekly', 'monthly', 'quarterly', 'yearly']);
    });
    test('schedule label by status', () {
      final d = DateTime(2026, 10, 1);
      expect(templateScheduleLabel(frequency: ChecklistFrequency.monthly, nextRun: d, status: 'active'),
          'Monthly · Next Oct 1');
      expect(templateScheduleLabel(frequency: ChecklistFrequency.monthly, nextRun: d, status: 'paused'),
          'Monthly · paused');
      expect(templateScheduleLabel(frequency: ChecklistFrequency.monthly, nextRun: d, status: 'ended'),
          'Monthly · ended');
    });
  });

  group('validateChecklist', () {
    test('needs a name and a step', () {
      expect(validateChecklist(title: ' ', steps: ['a']), isNotNull);
      expect(validateChecklist(title: 'Close', steps: []), isNotNull);
      expect(validateChecklist(title: 'Close', steps: ['a']), isNull);
    });
    test('template rules: repeats >= 1, end not before start', () {
      expect(validateChecklist(title: 'T', steps: ['a'], isTemplate: true, maxOccurrences: 0), isNotNull);
      expect(
        validateChecklist(
            title: 'T', steps: ['a'], isTemplate: true,
            start: DateTime(2026, 10, 1), end: DateTime(2026, 9, 1)),
        isNotNull,
      );
      expect(
        validateChecklist(
            title: 'T', steps: ['a'], isTemplate: true,
            start: DateTime(2026, 10, 1), end: DateTime(2027, 1, 1), maxOccurrences: 3),
        isNull,
      );
    });
  });
}
