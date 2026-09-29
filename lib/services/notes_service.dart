import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/note_status.dart';

/// Firm notes on the phone -- the internal accounting notes a firm keeps per
/// client. Same table and RPCs as the web's Notes page
/// (src/services/workspace-notes.service.ts), so anything done here is what
/// the desk sees. Model follows TaxDome's firm app: Active list, archive, and
/// an Archived list where a note is restored or deleted for good. The database
/// enforces the rules (LK001-LK005); this file only asks.
class WorkspaceNote {
  final String id;
  final String clientId;
  final String clientLabel;
  final String body;
  final String createdBy;
  final bool requiresApproval;
  final DateTime? approvedAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  final DateTime createdAt;

  WorkspaceNote.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        clientId = r['client_id'] as String,
        clientLabel = _label(r['clients'] as Map?),
        body = r['body'] as String,
        createdBy = r['created_by'] as String,
        requiresApproval = (r['requires_approval'] as bool?) ?? false,
        approvedAt = _date(r['approved_at']),
        dueAt = _date(r['due_at']),
        completedAt = _date(r['completed_at']),
        archivedAt = _date(r['archived_at']),
        createdAt = DateTime.parse(r['created_at'] as String);

  NoteStatus get status => noteStatus(
        archivedAt: archivedAt,
        approvedAt: approvedAt,
        completedAt: completedAt,
        requiresApproval: requiresApproval,
      );

  /// "Contact · Company", like the web's clientLabel (src/lib/client-name.ts).
  static String _label(Map? c) {
    final name = (c?['display_name'] as String?)?.trim();
    final company = (c?['company_name'] as String?)?.trim();
    final primary = (name != null && name.isNotEmpty) ? name : (company ?? 'Client');
    return (company != null && company.isNotEmpty && company != primary) ? '$primary · $company' : primary;
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
}

class NotesService {
  final _db = Supabase.instance.client;

  String? get userId => _db.auth.currentUser?.id;

  Future<List<WorkspaceNote>> list(String orgId) async {
    final rows = await _db
        .from('workspace_notes')
        .select('id, client_id, body, created_by, requires_approval, approved_at, due_at, '
            'completed_at, archived_at, created_at, clients(display_name, company_name)')
        .eq('org_id', orgId)
        .order('created_at', ascending: false);
    final notes = (rows as List).map((r) => WorkspaceNote.fromRow(Map<String, dynamic>.from(r as Map))).toList();
    // Task-list order, same as the web: open notes with a reminder soonest
    // first, then everything else newest first.
    int rank(WorkspaceNote n) => n.status == NoteStatus.open && n.dueAt != null ? 0 : 1;
    notes.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (rank(a) == 0) return a.dueAt!.compareTo(b.dueAt!);
      return b.createdAt.compareTo(a.createdAt);
    });
    return notes;
  }

  Future<void> create({
    required String orgId,
    required String clientId,
    required String body,
    bool requiresApproval = false,
    DateTime? dueAt,
  }) async {
    await _db.rpc('create_workspace_note', params: {
      'p_org_id': orgId,
      'p_client_id': clientId,
      'p_body': body,
      'p_requires_approval': requiresApproval,
      if (dueAt != null) 'p_due_at': dueAt.toUtc().toIso8601String(),
    });
  }

  Future<void> approve(String noteId) =>
      _db.rpc('approve_workspace_note', params: {'p_note_id': noteId});

  Future<void> complete(String noteId) =>
      _db.rpc('complete_workspace_note', params: {'p_note_id': noteId});

  Future<void> archive(String noteId, {bool archive = true}) =>
      _db.rpc('archive_workspace_note', params: {'p_note_id': noteId, 'p_archive': archive});

  Future<void> delete(String noteId) =>
      _db.rpc('delete_workspace_note', params: {'p_note_id': noteId});
}
