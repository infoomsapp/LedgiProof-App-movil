/// The rules of the Checklists screen that have nothing to do with Flutter:
/// who may manage them, what a schedule is called, how a typed list of steps
/// becomes rows, and how a task's due date reads. Kept here so they can be
/// tested and so the phone and the web state them the same way.
library;

/// Recurring schedules a template can run on (the database enum
/// recurring_frequency, same five values as the web).
enum ChecklistFrequency { weekly, biweekly, monthly, quarterly, yearly }

extension ChecklistFrequencyInfo on ChecklistFrequency {
  String get value => name;

  String get label => switch (this) {
        ChecklistFrequency.weekly => 'Weekly',
        ChecklistFrequency.biweekly => 'Every 2 weeks',
        ChecklistFrequency.monthly => 'Monthly',
        ChecklistFrequency.quarterly => 'Quarterly',
        ChecklistFrequency.yearly => 'Yearly',
      };
}

ChecklistFrequency? frequencyFrom(String? v) {
  for (final f in ChecklistFrequency.values) {
    if (f.name == v) return f;
  }
  return null;
}

/// Roles the checklist_runs / recurring_checklists write policies accept.
/// Ticking a task is wider on purpose: the run-items UPDATE policy lets any
/// member of the organization do it, so a bookkeeper without manage rights can
/// still work through a checklist someone else set up. A client of a firm is
/// not a member and sees nothing here.
const _manageRoles = {'owner', 'admin', 'accountant'};

bool canManageChecklists(String role, {required bool isPortalClient}) =>
    !isPortalClient && _manageRoles.contains(role);

bool canTickChecklists({required bool isPortalClient}) => !isPortalClient;

const maxChecklistSteps = 100;
const maxStepTitleLength = 200;

/// One step per line, as typed in the compose box. Blank lines and leading list
/// marks ("-", "*", "•", "1.", "1)") are dropped, titles are trimmed and capped,
/// and there is a ceiling on how many, so pasting a whole document cannot
/// create a thousand-row checklist.
List<String> parseSteps(String text) {
  final mark = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+');
  final steps = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    var line = raw.replaceFirst(mark, '').trim();
    if (line.isEmpty) continue;
    if (line.length > maxStepTitleLength) line = line.substring(0, maxStepTitleLength);
    steps.add(line);
    if (steps.length >= maxChecklistSteps) break;
  }
  return steps;
}

double runProgress(int total, int done) => total <= 0 ? 0 : done / total;

/// "3 of 5 done", "No tasks yet".
String runProgressLabel(int total, int done) =>
    total == 0 ? 'No tasks yet' : '$done of $total done';

enum TaskDue { none, overdue, today, soon, later }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// How a task's due date reads. A finished task never nags.
TaskDue taskDue({DateTime? dueAt, required bool done, DateTime? now}) {
  if (done || dueAt == null) return TaskDue.none;
  final days = _dateOnly(dueAt.toLocal()).difference(_dateOnly(now ?? DateTime.now())).inDays;
  if (days < 0) return TaskDue.overdue;
  if (days == 0) return TaskDue.today;
  if (days <= 3) return TaskDue.soon;
  return TaskDue.later;
}

/// "Overdue · 4 days", "Due today", "Due in 2 days", "Due Oct 3".
String taskDueLabel({required DateTime dueAt, DateTime? now}) {
  final due = _dateOnly(dueAt.toLocal());
  final days = due.difference(_dateOnly(now ?? DateTime.now())).inDays;
  String plural(int n) => '$n day${n == 1 ? '' : 's'}';
  if (days < 0) return 'Overdue · ${plural(-days)}';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days <= 6) return 'Due in ${plural(days)}';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Due ${m[due.month - 1]} ${due.day}';
}

/// "Next: Oct 1 · Monthly" for a template row.
String templateScheduleLabel({
  required ChecklistFrequency frequency,
  required DateTime nextRun,
  required String status,
}) {
  if (status == 'ended') return '${frequency.label} · ended';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final next = 'Next ${m[nextRun.month - 1]} ${nextRun.day}';
  return status == 'paused' ? '${frequency.label} · paused' : '${frequency.label} · $next';
}

/// Why a template or run cannot be saved yet, or null when it can.
String? validateChecklist({
  required String title,
  required List<String> steps,
  int? maxOccurrences,
  DateTime? start,
  DateTime? end,
  bool isTemplate = false,
}) {
  if (title.trim().isEmpty) return 'Give the checklist a name.';
  if (steps.isEmpty) return 'Add at least one step, one per line.';
  if (isTemplate) {
    if (maxOccurrences != null && maxOccurrences < 1) {
      return 'How many times it repeats must be at least 1.';
    }
    if (start != null && end != null && end.isBefore(start)) {
      return 'The end date is before the start date.';
    }
  }
  return null;
}
