import 'package:flutter/material.dart';
import '../services/checklist_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// Checklist runs for the workspace, with their items tickable in place.
class ChecklistsScreen extends StatefulWidget {
  final Workspace workspace;
  const ChecklistsScreen({super.key, required this.workspace});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  final _service = ChecklistService();
  late Future<List<ChecklistRun>> _runs;

  @override
  void initState() {
    super.initState();
    _runs = _service.loadRuns(widget.workspace.orgId);
  }

  void _reload() {
    setState(() => _runs = _service.loadRuns(widget.workspace.orgId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklists',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<ChecklistRun>>(
        future: _runs,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Empty(
              icon: Icons.error_outline,
              title: 'Could not load checklists.',
              body: 'Check your connection and pull to retry.',
              onRetry: _reload,
            );
          }
          final runs = snap.data ?? [];
          if (runs.isEmpty) {
            return _Empty(
              icon: Icons.checklist_outlined,
              title: 'No checklists yet.',
              body: 'Recurring checklists are set up on the web app; the runs '
                  'they generate show up here.',
              onRetry: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: runs.length,
              itemBuilder: (context, i) => _RunCard(
                run: runs[i],
                service: _service,
                onChanged: _reload,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RunCard extends StatefulWidget {
  final ChecklistRun run;
  final ChecklistService service;
  final VoidCallback onChanged;

  const _RunCard(
      {required this.run, required this.service, required this.onChanged});

  @override
  State<_RunCard> createState() => _RunCardState();
}

class _RunCardState extends State<_RunCard> {
  bool _open = false;
  Future<List<ChecklistItem>>? _items;

  void _toggle() {
    setState(() {
      _open = !_open;
      _items ??= widget.service.loadItems(widget.run.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          run.title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink),
                        ),
                      ),
                      Icon(_open ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: AppColors.inkMuted),
                    ],
                  ),
                  if (run.clientName != null) ...[
                    const SizedBox(height: 3),
                    Text(run.clientName!,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.inkMuted)),
                  ],
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: run.progress,
                      minHeight: 5,
                      backgroundColor: AppColors.surface2,
                      valueColor: AlwaysStoppedAnimation(
                          run.isComplete ? AppColors.green : AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${run.doneItems} of ${run.totalItems} done',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            FutureBuilder<List<ChecklistItem>>(
              future: _items,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                    ),
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Text('This checklist has no items.',
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  );
                }
                return Column(
                  children: [
                    Divider(height: 1, thickness: 1, color: AppColors.border),
                    ...items.map((item) => _ItemRow(
                          item: item,
                          onToggle: (done) async {
                            await widget.service.setItemDone(item.id, done);
                            setState(() =>
                                _items = widget.service.loadItems(widget.run.id));
                            widget.onChanged();
                          },
                        )),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ChecklistItem item;
  final Future<void> Function(bool) onToggle;
  const _ItemRow({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!item.done),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              item.done ? Icons.check_circle : Icons.circle_outlined,
              size: 19,
              color: item.done ? AppColors.green : AppColors.inkSubtle,
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
                      decoration:
                          item.done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.inkMuted,
                    ),
                  ),
                  if (item.description != null &&
                      item.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.description!,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.inkSubtle)),
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

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onRetry;
  const _Empty(
      {required this.icon,
      required this.title,
      required this.body,
      required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.inkSubtle),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}
