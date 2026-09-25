import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/checklist_logic.dart';

/// Checklists on the phone: the runs a firm works through, and the recurring
/// templates that generate them. Same tables, same columns and same RPC as the
/// web app's Checklists page (src/services/recurring-checklist.service.ts), so
/// anything done here is what the desk sees, and the reverse -- both sides also
/// listen for each other's changes (see ChecklistLive).
///
/// Row Level Security does not raise an error for a write the caller may not
/// make, it just matches zero rows. Every write below therefore asks for the
/// rows it changed and throws when there are none, so a role without permission
/// is told so instead of watching a change silently not happen.

class ChecklistRun {
  final String id;
  final String title;
  final String status; // open | completed
  final DateTime? runDate;
  final String? clientId;
  final String? clientName;
  final bool fromTemplate;
  final int totalItems;
  final int doneItems;

  ChecklistRun({
    required this.id,
    required this.title,
    required this.status,
    required this.runDate,
    required this.clientId,
    required this.clientName,
    required this.fromTemplate,
    required this.totalItems,
    required this.doneItems,
  });

  double get progress => runProgress(totalItems, doneItems);
  bool get isCompleted => status == 'completed';
  bool get allDone => totalItems > 0 && doneItems == totalItems;
}

class ChecklistItem {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final DateTime? completedAt;

  ChecklistItem({
    required this.id,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.completedAt,
  });

  bool get done => completedAt != null;
}

class RecurringChecklist {
  final String id;
  final String title;
  final String? clientId;
  final String? clientName;
  final ChecklistFrequency frequency;
  final DateTime nextRunDate;
  final DateTime? endDate;
  final int? maxOccurrences;
  final int occurrencesGenerated;
  final String status; // active | paused | ended
  final int stepCount;

  RecurringChecklist({
    required this.id,
    required this.title,
    required this.clientId,
    required this.clientName,
    required this.frequency,
    required this.nextRunDate,
    required this.endDate,
    required this.maxOccurrences,
    required this.occurrencesGenerated,
    required this.status,
    required this.stepCount,
  });

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isEnded => status == 'ended';
}

class ChecklistService {
  final _db = Supabase.instance.client;

  String? get _userId => _db.auth.currentUser?.id;

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  static String? _clientName(Object? c) => c == null
      ? null
      : (c as Map)['display_name'] as String?;

  // ── Runs ──────────────────────────────────────────────────────────────────

  /// Runs with their progress in ONE query (the items come embedded and only
  /// their completed_at is read), newest first. Explicit column lists
  /// throughout: `select('*')` is what once shipped an encrypted token to every
  /// browser, and there is no reason to repeat the pattern here.
  Future<List<ChecklistRun>> loadRuns(String orgId, {String? status, int limit = 100}) async {
    var q = _db
        .from('checklist_runs')
        .select('id, title, status, run_date, client_id, recurring_id, '
            'clients(display_name), checklist_run_items(completed_at)')
        .eq('org_id', orgId);
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('run_date', ascending: false).limit(limit);

    return (rows as List).map((raw) {
      final r = Map<String, dynamic>.from(raw as Map);
      final items = (r['checklist_run_items'] as List?) ?? const [];
      return ChecklistRun(
        id: r['id'] as String,
        title: (r['title'] as String?) ?? 'Checklist',
        status: (r['status'] as String?) ?? 'open',
        runDate: r['run_date'] == null ? null : DateTime.tryParse(r['run_date'] as String),
        clientId: r['client_id'] as String?,
        clientName: _clientName(r['clients']),
        fromTemplate: r['recurring_id'] != null,
        totalItems: items.length,
        doneItems: items.where((i) => (i as Map)['completed_at'] != null).length,
      );
    }).toList();
  }

  /// One run with its progress, or null when it no longer exists (deleted on
  /// the web while this screen was open).
  Future<ChecklistRun?> loadRun(String runId) async {
    final raw = await _db
        .from('checklist_runs')
        .select('id, title, status, run_date, client_id, recurring_id, '
            'clients(display_name), checklist_run_items(completed_at)')
        .eq('id', runId)
        .maybeSingle();
    if (raw == null) return null;
    final r = Map<String, dynamic>.from(raw);
    final items = (r['checklist_run_items'] as List?) ?? const [];
    return ChecklistRun(
      id: r['id'] as String,
      title: (r['title'] as String?) ?? 'Checklist',
      status: (r['status'] as String?) ?? 'open',
      runDate: r['run_date'] == null ? null : DateTime.tryParse(r['run_date'] as String),
      clientId: r['client_id'] as String?,
      clientName: _clientName(r['clients']),
      fromTemplate: r['recurring_id'] != null,
      totalItems: items.length,
      doneItems: items.where((i) => (i as Map)['completed_at'] != null).length,
    );
  }

  Future<List<ChecklistItem>> loadItems(String runId) async {
    final rows = await _db
        .from('checklist_run_items')
        .select('id, title, description, due_at, completed_at, sort_order')
        .eq('run_id', runId)
        .order('sort_order', ascending: true);

    return (rows as List)
        .map((r) => ChecklistItem(
              id: r['id'] as String,
              title: (r['title'] as String?) ?? 'Item',
              description: r['description'] as String?,
              dueAt: r['due_at'] == null ? null : DateTime.tryParse(r['due_at'] as String),
              completedAt:
                  r['completed_at'] == null ? null : DateTime.tryParse(r['completed_at'] as String),
            ))
        .toList();
  }

  /// Ticking a task writes completed_at / completed_by, the same two columns the
  /// web sets, so a box ticked on the phone shows as done on the desk. Any
  /// member of the organization may tick (run-items UPDATE policy).
  Future<void> setItemDone(String itemId, bool done) async {
    final updated = await _db
        .from('checklist_run_items')
        .update({
          'completed_at': done ? DateTime.now().toUtc().toIso8601String() : null,
          'completed_by': done ? _userId : null,
        })
        .eq('id', itemId)
        .select('id');
    _mustChange(updated, 'You cannot change tasks in this checklist.');
  }

  /// Adds a task at the end of a run.
  Future<void> addItem({
    required String runId,
    required String orgId,
    required String title,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) throw StateError('Type the task first.');
    final last = await _db
        .from('checklist_run_items')
        .select('sort_order')
        .eq('run_id', runId)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((last?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    final inserted = await _db
        .from('checklist_run_items')
        .insert({
          'run_id': runId,
          'org_id': orgId,
          'sort_order': next,
          'title': clean.length > maxStepTitleLength ? clean.substring(0, maxStepTitleLength) : clean,
        })
        .select('id');
    _mustChange(inserted, 'Only an owner, admin or accountant can add tasks.');
  }

  Future<void> deleteItem(String itemId) async {
    final deleted =
        await _db.from('checklist_run_items').delete().eq('id', itemId).select('id');
    _mustChange(deleted, 'Only an owner, admin or accountant can remove tasks.');
  }

  /// A one-off checklist (not tied to a schedule), e.g. onboarding one client.
  Future<String> createRun({
    required String orgId,
    required String title,
    required DateTime runDate,
    required List<String> steps,
    String? clientId,
  }) async {
    final run = await _db
        .from('checklist_runs')
        .insert({
          'org_id': orgId,
          'client_id': clientId,
          'created_by': _userId,
          'title': title.trim(),
          'run_date': _iso(runDate),
        })
        .select('id')
        .single();
    final runId = run['id'] as String;
    if (steps.isNotEmpty) {
      await _db.from('checklist_run_items').insert([
        for (var i = 0; i < steps.length; i++)
          {'run_id': runId, 'org_id': orgId, 'sort_order': i, 'title': steps[i]},
      ]);
    }
    return runId;
  }

  Future<void> completeRun(String runId) async {
    final updated = await _db
        .from('checklist_runs')
        .update({'status': 'completed', 'completed_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', runId)
        .select('id');
    _mustChange(updated, 'Only an owner, admin or accountant can complete a checklist.');
  }

  /// Puts a completed run back to open (the web has no button for it, but a
  /// checklist completed by mistake should not be a dead end on the phone).
  Future<void> reopenRun(String runId) async {
    final updated = await _db
        .from('checklist_runs')
        .update({'status': 'open', 'completed_at': null})
        .eq('id', runId)
        .select('id');
    _mustChange(updated, 'Only an owner, admin or accountant can reopen a checklist.');
  }

  Future<void> deleteRun(String runId) async {
    final deleted = await _db.from('checklist_runs').delete().eq('id', runId).select('id');
    _mustChange(deleted, 'Only an owner, admin or accountant can delete a checklist.');
  }

  // ── Recurring templates ───────────────────────────────────────────────────

  Future<List<RecurringChecklist>> loadTemplates(String orgId) async {
    final rows = await _db
        .from('recurring_checklists')
        .select('id, title, client_id, frequency, next_run_date, end_date, '
            'max_occurrences, occurrences_generated, status, '
            'clients(display_name), recurring_checklist_items(id)')
        .eq('org_id', orgId)
        .order('next_run_date', ascending: true);

    return (rows as List).map((raw) {
      final r = Map<String, dynamic>.from(raw as Map);
      return RecurringChecklist(
        id: r['id'] as String,
        title: (r['title'] as String?) ?? 'Checklist',
        clientId: r['client_id'] as String?,
        clientName: _clientName(r['clients']),
        frequency: frequencyFrom(r['frequency'] as String?) ?? ChecklistFrequency.monthly,
        nextRunDate: DateTime.tryParse((r['next_run_date'] as String?) ?? '') ?? DateTime.now(),
        endDate: r['end_date'] == null ? null : DateTime.tryParse(r['end_date'] as String),
        maxOccurrences: (r['max_occurrences'] as num?)?.toInt(),
        occurrencesGenerated: (r['occurrences_generated'] as num?)?.toInt() ?? 0,
        status: (r['status'] as String?) ?? 'active',
        stepCount: ((r['recurring_checklist_items'] as List?) ?? const []).length,
      );
    }).toList();
  }

  Future<List<String>> loadTemplateSteps(String templateId) async {
    final rows = await _db
        .from('recurring_checklist_items')
        .select('title, sort_order')
        .eq('recurring_id', templateId)
        .order('sort_order', ascending: true);
    return (rows as List).map((r) => (r['title'] as String?) ?? '').where((t) => t.isNotEmpty).toList();
  }

  Future<void> createTemplate({
    required String orgId,
    required String title,
    required ChecklistFrequency frequency,
    required DateTime startDate,
    required List<String> steps,
    String? clientId,
    DateTime? endDate,
    int? maxOccurrences,
  }) async {
    final rec = await _db
        .from('recurring_checklists')
        .insert({
          'org_id': orgId,
          'client_id': clientId,
          'created_by': _userId,
          'title': title.trim(),
          'frequency': frequency.value,
          'next_run_date': _iso(startDate),
          'end_date': endDate == null ? null : _iso(endDate),
          'max_occurrences': maxOccurrences,
        })
        .select('id')
        .single();
    final id = rec['id'] as String;
    if (steps.isNotEmpty) {
      await _db.from('recurring_checklist_items').insert([
        for (var i = 0; i < steps.length; i++)
          {'recurring_id': id, 'org_id': orgId, 'sort_order': i, 'title': steps[i]},
      ]);
    }
  }

  /// active | paused | ended.
  Future<void> setTemplateStatus(String id, String status) async {
    final updated = await _db
        .from('recurring_checklists')
        .update({'status': status, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    _mustChange(updated, 'Only an owner, admin or accountant can change a schedule.');
  }

  Future<void> deleteTemplate(String id) async {
    final deleted = await _db.from('recurring_checklists').delete().eq('id', id).select('id');
    _mustChange(deleted, 'Only an owner, admin or accountant can delete a schedule.');
  }

  /// Runs the schedule generator for everything due today or earlier -- the
  /// same RPC as the web's "Generate now". Returns how many checklists it made.
  Future<int> generateDue(String orgId) async {
    final res = await _db.rpc('generate_due_recurring_checklists', params: {'p_org_id': orgId});
    final map = res is Map ? res : const {};
    final err = map['error'] as String?;
    if (err != null) throw StateError(err);
    return (map['generated'] as num?)?.toInt() ?? 0;
  }

  static void _mustChange(Object? rows, String message) {
    if (rows is List && rows.isEmpty) throw StateError(message);
  }
}

/// Listens for changes to an organization's checklist data, from the web or
/// another phone, and calls [onChange] once per burst. Row Level Security
/// decides which events a session receives. Reconnecting counts as a change:
/// events may have been lost in the gap.
class ChecklistLive {
  final RealtimeChannel _channel;
  Timer? _timer;
  bool _subscribedBefore = false;

  ChecklistLive._(this._channel);

  static ChecklistLive start({
    required String orgId,
    required void Function() onChange,
    String? runId,
  }) {
    final db = Supabase.instance.client;
    late final ChecklistLive live;
    void fire() {
      live._timer?.cancel();
      live._timer = Timer(const Duration(milliseconds: 300), onChange);
    }

    PostgresChangeFilter orgFilter() => PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'org_id',
          value: orgId,
        );

    var channel = db.channel('checklists-$orgId${runId == null ? '' : '-$runId'}');
    for (final table in const [
      'checklist_runs',
      'checklist_run_items',
      'recurring_checklists',
      'recurring_checklist_items',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: orgFilter(),
        callback: (_) => fire(),
      );
    }
    live = ChecklistLive._(channel);
    channel.subscribe((status, _) {
      if (status != RealtimeSubscribeStatus.subscribed) return;
      if (live._subscribedBefore) fire();
      live._subscribedBefore = true;
    });
    return live;
  }

  void stop() {
    _timer?.cancel();
    Supabase.instance.client.removeChannel(_channel);
  }
}
