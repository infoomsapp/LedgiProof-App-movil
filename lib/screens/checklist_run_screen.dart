import 'package:flutter/material.dart';
import '../services/checklist_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/checklist_logic.dart';
import '../utils/errors.dart';

/// One checklist: tick tasks off, add a task, complete or reopen the checklist,
/// delete it. Ticking is open to every member; adding, removing, completing and
/// deleting need owner/admin/accountant (what the policies allow), so those
/// controls only appear for them. It listens for changes made elsewhere (the
/// web, another phone) and updates in place.
class ChecklistRunScreen extends StatefulWidget {
  final Workspace workspace;
  final String runId;
  const ChecklistRunScreen({super.key, required this.workspace, required this.runId});

  @override
  State<ChecklistRunScreen> createState() => _ChecklistRunScreenState();
}

class _ChecklistRunScreenState extends State<ChecklistRunScreen> {
  final _service = ChecklistService();
  final _newTask = TextEditingController();
  ChecklistLive? _live;

  ChecklistRun? _run;
  List<ChecklistItem>? _items;
  bool _gone = false; // deleted elsewhere while open
  bool _loading = true;
  bool _busy = false;
  final Set<String> _pending = {}; // tasks whose tick is being saved

  bool get _canManage => canManageChecklists(
        widget.workspace.role,
        isPortalClient: widget.workspace.isPortalClient,
      );
  bool get _canTick => canTickChecklists(isPortalClient: widget.workspace.isPortalClient);

  @override
  void initState() {
    super.initState();
    _load();
    _live = ChecklistLive.start(
      orgId: widget.workspace.orgId,
      runId: widget.runId,
      onChange: _load,
    );
  }

  @override
  void dispose() {
    _live?.stop();
    _newTask.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.loadRun(widget.runId),
        _service.loadItems(widget.runId),
      ]);
      if (!mounted) return;
      final run = results[0] as ChecklistRun?;
      setState(() {
        _run = run;
        _gone = run == null;
        _items = results[1] as List<ChecklistItem>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false); // keep what is on screen
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _tick(ChecklistItem item) async {
    if (!_canTick || _pending.contains(item.id)) return;
    final nowDone = !item.done;
    // Show the tick immediately; the server answer (or the realtime echo)
    // settles it. If the write is refused it snaps back with the reason.
    setState(() {
      _pending.add(item.id);
      _items = [
        for (final i in _items!)
          if (i.id == item.id)
            ChecklistItem(
              id: i.id,
              title: i.title,
              description: i.description,
              dueAt: i.dueAt,
              completedAt: nowDone ? DateTime.now() : null,
            )
          else
            i,
      ];
    });
    try {
      await _service.setItemDone(item.id, nowDone);
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      _pending.remove(item.id);
      await _load();
    }
  }

  Future<void> _add() async {
    final text = _newTask.text;
    if (text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.addItem(
        runId: widget.runId,
        orgId: widget.workspace.orgId,
        title: text,
      );
      _newTask.clear(); // only once it is saved: never lose what was typed
      await _load();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeTask(ChecklistItem item) async {
    final ok = await _confirm('Remove this task?', item.title, 'Remove');
    if (ok != true) return;
    try {
      await _service.deleteItem(item.id);
      await _load();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<bool?> _confirm(String title, String body, String action) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(action, style: TextStyle(color: AppColors.red))),
          ],
        ),
      );

  Future<void> _setCompleted(bool complete) async {
    setState(() => _busy = true);
    try {
      if (complete) {
        await _service.completeRun(widget.runId);
        _snack('Checklist completed.');
      } else {
        await _service.reopenRun(widget.runId);
        _snack('Checklist reopened.');
      }
      await _load();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRun() async {
    final ok = await _confirm(
        'Delete this checklist?', 'It and all its tasks are removed. This cannot be undone.', 'Delete');
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _service.deleteRun(widget.runId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack(friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Scaffold(
      appBar: AppBar(
        title: Text(run?.title ?? 'Checklist',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          if (_canManage && run != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'complete') _setCompleted(true);
                if (v == 'reopen') _setCompleted(false);
                if (v == 'delete') _deleteRun();
              },
              itemBuilder: (_) => [
                if (!run.isCompleted)
                  const PopupMenuItem(value: 'complete', child: Text('Mark complete')),
                if (run.isCompleted)
                  const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                const PopupMenuItem(value: 'delete', child: Text('Delete checklist')),
              ],
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_gone) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('This checklist was deleted.',
              style: TextStyle(color: AppColors.inkMuted)),
        ),
      );
    }
    final run = _run;
    final items = _items;
    if (run == null || items == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Could not load this checklist.'));
    }
    final done = items.where((i) => i.done).length;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _Header(run: run, total: items.length, done: done),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('No tasks yet.',
                          style: TextStyle(color: AppColors.inkMuted)),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.border),
                          _TaskRow(
                            item: items[i],
                            canTick: _canTick,
                            pending: _pending.contains(items[i].id),
                            onTick: () => _tick(items[i]),
                            onLongPress: _canManage ? () => _removeTask(items[i]) : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_canManage && done == items.length && items.isNotEmpty && !run.isCompleted) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _setCompleted(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('All done — mark complete',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (_canManage)
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTask,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: maxStepTitleLength,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                        hintText: 'Add a task…',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: 'Add task',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final ChecklistRun run;
  final int total;
  final int done;
  const _Header({required this.run, required this.total, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
                child: Text(
                  [
                    if (run.clientName != null) run.clientName!,
                    if (run.fromTemplate) 'Scheduled',
                    if (run.isCompleted) 'Completed',
                  ].join(' · ').isEmpty
                      ? 'One-off checklist'
                      : [
                          if (run.clientName != null) run.clientName!,
                          if (run.fromTemplate) 'Scheduled',
                          if (run.isCompleted) 'Completed',
                        ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: runProgress(total, done),
              minHeight: 6,
              backgroundColor: AppColors.surface2,
              valueColor: AlwaysStoppedAnimation(
                  run.isCompleted || (total > 0 && done == total) ? AppColors.green : AppColors.primary),
            ),
          ),
          const SizedBox(height: 7),
          Text(runProgressLabel(total, done),
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final ChecklistItem item;
  final bool canTick;
  final bool pending;
  final VoidCallback onTick;
  final VoidCallback? onLongPress;
  const _TaskRow({
    required this.item,
    required this.canTick,
    required this.pending,
    required this.onTick,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final due = taskDue(dueAt: item.dueAt, done: item.done);
    final dueColor = switch (due) {
      TaskDue.overdue => AppColors.red,
      TaskDue.today || TaskDue.soon => AppColors.amber,
      _ => AppColors.inkSubtle,
    };
    return InkWell(
      onTap: canTick ? onTick : null,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: pending ? 0.5 : 1,
              child: Icon(
                item.done ? Icons.check_circle : Icons.circle_outlined,
                size: 21,
                color: item.done ? AppColors.green : AppColors.inkSubtle,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: item.done ? AppColors.inkMuted : AppColors.ink,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.inkMuted,
                    ),
                  ),
                  if ((item.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.description!,
                        style: TextStyle(fontSize: 12, color: AppColors.inkSubtle)),
                  ],
                  if (due != TaskDue.none && item.dueAt != null) ...[
                    const SizedBox(height: 3),
                    Text(taskDueLabel(dueAt: item.dueAt!),
                        style: TextStyle(fontSize: 11.5, color: dueColor)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
