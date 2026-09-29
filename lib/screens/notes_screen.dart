import 'package:flutter/material.dart';
import '../services/notes_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/doc_format.dart';
import '../utils/errors.dart';
import '../utils/note_status.dart';
import '../widgets/client_picker_sheet.dart';

/// Firm notes across every client -- the phone twin of the web's Notes page.
/// Filters, approve, mark done, archive; the Archived filter is where a note
/// is restored or deleted for good (TaxDome's firm app works the same way).
class NotesScreen extends StatefulWidget {
  final Workspace workspace;
  const NotesScreen({super.key, required this.workspace});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

enum _Filter {
  all('All'),
  open('Open'),
  pending('Pending approval'),
  approved('Approved'),
  done('Done'),
  archived('Archived');

  final String label;
  const _Filter(this.label);

  bool matches(NoteStatus s) => switch (this) {
        _Filter.all => s != NoteStatus.archived,
        _Filter.open => s == NoteStatus.open,
        _Filter.pending => s == NoteStatus.pendingApproval,
        _Filter.approved => s == NoteStatus.approved,
        _Filter.done => s == NoteStatus.done,
        _Filter.archived => s == NoteStatus.archived,
      };
}

class _NotesScreenState extends State<NotesScreen> {
  final _service = NotesService();
  List<WorkspaceNote>? _notes;
  String? _loadError;
  _Filter _filter = _Filter.all;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.list(widget.workspace.orgId);
      if (mounted) setState(() { _notes = rows; _loadError = null; });
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e, 'Could not load notes.'));
    }
  }

  Future<void> _run(String noteId, Future<void> Function() action, String fallback) async {
    setState(() => _busyId = noteId);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback))));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(WorkspaceNote n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('It is removed for good. The audit log keeps a fingerprint of it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await _run(n.id, () => _service.delete(n.id), 'Could not delete the note.');
  }

  Future<void> _newNote() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _NewNoteSheet(orgId: widget.workspace.orgId, service: _service),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    final shown = notes?.where((n) => _filter.matches(n.status)).toList() ?? const <WorkspaceNote>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newNote,
        icon: const Icon(Icons.add),
        label: const Text('Note'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_loadError!, style: TextStyle(fontSize: 12, color: AppColors.amber)),
              ),
            if (notes == null && _loadError == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    _filter == _Filter.all ? 'No notes yet' : 'Nothing in this filter',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              )
            else
              for (final n in shown)
                _NoteCard(
                  note: n,
                  busy: _busyId == n.id,
                  canApprove: canApproveNote(
                    status: n.status,
                    role: widget.workspace.role,
                    createdBy: n.createdBy,
                    userId: _service.userId ?? '',
                  ),
                  onApprove: () => _run(n.id, () => _service.approve(n.id), 'Could not approve the note.'),
                  onComplete: () => _run(n.id, () => _service.complete(n.id), 'Could not complete the note.'),
                  onArchive: () => _run(n.id, () => _service.archive(n.id), 'Could not archive the note.'),
                  onRestore: () =>
                      _run(n.id, () => _service.archive(n.id, archive: false), 'Could not restore the note.'),
                  onDelete: () => _delete(n),
                ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final WorkspaceNote note;
  final bool busy;
  final bool canApprove;
  final VoidCallback onApprove, onComplete, onArchive, onRestore, onDelete;

  const _NoteCard({
    required this.note,
    required this.busy,
    required this.canApprove,
    required this.onApprove,
    required this.onComplete,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = note.status;
    final (Color fg, Color bg) = switch (status) {
      NoteStatus.approved || NoteStatus.done => (AppColors.green, AppColors.greenBg),
      NoteStatus.pendingApproval => (AppColors.amber, AppColors.amberBg),
      _ => (AppColors.inkMuted, AppColors.surface2),
    };
    final archived = status == NoteStatus.archived;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(note.clientLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Text(noteStatusLabel(status), style: TextStyle(fontSize: 10.5, color: fg)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note.body, style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4)),
          if (note.dueAt != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.schedule, size: 12, color: AppColors.inkSubtle),
              const SizedBox(width: 4),
              Text(formatDocDate(note.dueAt!), style: TextStyle(fontSize: 11, color: AppColors.inkSubtle)),
            ]),
          ],
          const SizedBox(height: 8),
          if (busy)
            const SizedBox(height: 28, child: Center(child: LinearProgressIndicator()))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (canApprove) _action('Approve', Icons.check, AppColors.green, onApprove),
                if (canCompleteNote(status, note.requiresApproval))
                  _action('Mark done', Icons.done_all, AppColors.inkMuted, onComplete),
                if (archived) ...[
                  _action('Restore', Icons.unarchive_outlined, AppColors.primary, onRestore),
                  _action('Delete', Icons.delete_outline, AppColors.red, onDelete),
                ] else
                  _action('Archive', Icons.archive_outlined, AppColors.inkMuted, onArchive),
              ],
            ),
        ],
      ),
    );
  }

  Widget _action(String label, IconData icon, Color color, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(fontSize: 12, color: color)),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: BorderSide(color: AppColors.border),
        ),
      );
}

class _NewNoteSheet extends StatefulWidget {
  final String orgId;
  final NotesService service;
  const _NewNoteSheet({required this.orgId, required this.service});

  @override
  State<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends State<_NewNoteSheet> {
  final _body = TextEditingController();
  String? _clientId;
  String? _clientLabel;
  bool _requiresApproval = false;
  DateTime? _dueAt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickClient() async {
    final c = await pickClient(context, orgId: widget.orgId);
    if (c == null) return;
    final company = c.companyName?.trim();
    setState(() {
      _clientId = c.id;
      _clientLabel = (company != null && company.isNotEmpty && company != c.displayName)
          ? '${c.displayName} · $company'
          : c.displayName;
    });
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (!mounted) return;
    setState(() => _dueAt = DateTime(day.year, day.month, day.day, time?.hour ?? 9, time?.minute ?? 0));
  }

  Future<void> _save() async {
    if (_clientId == null || _body.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.service.create(
        orgId: widget.orgId,
        clientId: _clientId!,
        body: _body.text.trim(),
        requiresApproval: _requiresApproval,
        dueAt: _dueAt,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e, 'Could not save the note.'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving && _clientId != null && _body.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New note', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickClient,
            icon: const Icon(Icons.person_outline, size: 18),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(_clientLabel ?? 'Choose a client', overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Note…'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _requiresApproval,
            onChanged: _saving ? null : (v) => setState(() => _requiresApproval = v),
            title: const Text("Requires a second person's approval", style: TextStyle(fontSize: 13)),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _pickReminder,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_dueAt == null ? 'Add reminder' : 'Reminder · ${formatDocDate(_dueAt!)}'),
              ),
              if (_dueAt != null)
                IconButton(
                  onPressed: () => setState(() => _dueAt = null),
                  icon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.red)),
            ),
          FilledButton(
            onPressed: canSave ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save note'),
          ),
        ],
      ),
    );
  }
}
