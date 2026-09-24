import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the same checklist_runs / checklist_run_items tables the web app's
/// Checklists page uses (src/services/recurring-checklist.service.ts). Only the
/// run side is exposed here: generating runs from recurring templates stays a
/// desk job on the web.
class ChecklistRun {
  final String id;
  final String title;
  final String status;
  final DateTime? runDate;
  final String? clientName;
  final int totalItems;
  final int doneItems;

  ChecklistRun({
    required this.id,
    required this.title,
    required this.status,
    required this.runDate,
    required this.clientName,
    required this.totalItems,
    required this.doneItems,
  });

  double get progress => totalItems == 0 ? 0 : doneItems / totalItems;
  bool get isComplete => totalItems > 0 && doneItems == totalItems;
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

class ChecklistService {
  final _db = Supabase.instance.client;

  /// Open runs first, most recent first. Explicit column lists throughout:
  /// `select('*')` is what shipped the encrypted Plaid token to every browser
  /// on the web side, and there is no reason to repeat the pattern here.
  Future<List<ChecklistRun>> loadRuns(String orgId, {int limit = 50}) async {
    final rows = await _db
        .from('checklist_runs')
        .select('id, title, status, run_date, clients(display_name)')
        .eq('org_id', orgId)
        .order('run_date', ascending: false)
        .limit(limit);

    final runs = <ChecklistRun>[];
    for (final r in (rows as List)) {
      final id = r['id'] as String;
      final counts = await _db
          .from('checklist_run_items')
          .select('completed_at')
          .eq('run_id', id);

      final items = counts as List;
      runs.add(ChecklistRun(
        id: id,
        title: (r['title'] as String?) ?? 'Checklist',
        status: (r['status'] as String?) ?? 'open',
        runDate: r['run_date'] == null
            ? null
            : DateTime.tryParse(r['run_date'] as String),
        clientName: r['clients'] == null
            ? null
            : (r['clients'] as Map)['display_name'] as String?,
        totalItems: items.length,
        doneItems: items.where((i) => i['completed_at'] != null).length,
      ));
    }
    return runs;
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
              dueAt: r['due_at'] == null
                  ? null
                  : DateTime.tryParse(r['due_at'] as String),
              completedAt: r['completed_at'] == null
                  ? null
                  : DateTime.tryParse(r['completed_at'] as String),
            ))
        .toList();
  }

  /// Ticking an item writes completed_at / completed_by, the same two columns
  /// the web app sets, so a box ticked on the phone shows as done on the desk.
  Future<void> setItemDone(String itemId, bool done) async {
    final userId = _db.auth.currentUser?.id;
    await _db.from('checklist_run_items').update({
      'completed_at': done ? DateTime.now().toUtc().toIso8601String() : null,
      'completed_by': done ? userId : null,
    }).eq('id', itemId);
  }
}
