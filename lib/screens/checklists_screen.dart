import 'package:flutter/material.dart';
import '../services/checklist_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/checklist_logic.dart';
import '../utils/errors.dart';
import 'checklist_compose_screen.dart';
import 'checklist_run_screen.dart';

String _day(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

/// Checklists, start to finish on the phone: the runs a firm works through
/// (tick, add tasks, complete, delete), and the recurring templates that
/// generate them (create, pause, end, delete, generate what is due). Everything
/// reads and writes the same tables as the web's Checklists page, and both sides
/// hear each other's changes live, so nothing needs the desk any more.
class ChecklistsScreen extends StatefulWidget {
  final Workspace workspace;
  const ChecklistsScreen({super.key, required this.workspace});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen>
    with SingleTickerProviderStateMixin {
  final _service = ChecklistService();
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {}); // the floating button follows the tab
    });
  ChecklistLive? _live;

  // Last good data: a reload never blanks the screen, and a failed one keeps it.
  List<ChecklistRun>? _runs;
  List<RecurringChecklist>? _templates;
  Object? _error;
  bool _loading = true;
  bool _showCompleted = false;
  bool _generating = false;

  bool get _canManage => canManageChecklists(
        widget.workspace.role,
        isPortalClient: widget.workspace.isPortalClient,
      );

  @override
  void initState() {
    super.initState();
    _loadAll();
    _live = ChecklistLive.start(orgId: widget.workspace.orgId, onChange: _loadAll);
  }

  @override
  void dispose() {
    _live?.stop();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        _service.loadRuns(widget.workspace.orgId),
        _service.loadTemplates(widget.workspace.orgId),
      ]);
      if (!mounted) return;
      setState(() {
        _runs = results[0] as List<ChecklistRun>;
        _templates = results[1] as List<RecurringChecklist>;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _compose(ChecklistComposeMode mode) async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ChecklistComposeScreen(workspace: widget.workspace, mode: mode),
    ));
    if (created == true) _loadAll();
  }

  Future<void> _generateDue() async {
    setState(() => _generating = true);
    try {
      final n = await _service.generateDue(widget.workspace.orgId);
      _snack(n == 0 ? 'Nothing is due yet.' : 'Created $n checklist${n == 1 ? '' : 's'}.');
      _loadAll();
    } catch (e) {
      _snack('Could not generate: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onRuns = _tabs.index == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklists',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          if (_canManage && !onRuns)
            IconButton(
              onPressed: _generating ? null : _generateDue,
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Generate what is due',
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Runs'), Tab(text: 'Templates')],
        ),
      ),
      body: _body(),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: () => _compose(onRuns ? ChecklistComposeMode.run : ChecklistComposeMode.template),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, size: 20),
              label: Text(onRuns ? 'Checklist' : 'Template'),
            )
          : null,
    );
  }

  Widget _body() {
    if (_runs == null || _templates == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _Empty(
        icon: Icons.error_outline,
        title: 'Could not load checklists.',
        body: 'Check your connection and try again.',
        onRetry: _loadAll,
      );
    }
    return TabBarView(
      controller: _tabs,
      children: [_runsTab(), _templatesTab()],
    );
  }

  Widget _runsTab() {
    final all = _runs!;
    final shown = all.where((r) => r.isCompleted == _showCompleted).toList();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('Open ${all.where((r) => !r.isCompleted).length}')),
              ButtonSegment(value: true, label: Text('Completed ${all.where((r) => r.isCompleted).length}')),
            ],
            selected: {_showCompleted},
            onSelectionChanged: (s) => setState(() => _showCompleted = s.first),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Could not refresh. Showing what was loaded.',
                  style: TextStyle(fontSize: 12, color: AppColors.amber)),
            ),
          if (shown.isEmpty)
            _Empty(
              icon: Icons.checklist_outlined,
              title: _showCompleted ? 'Nothing completed yet.' : 'No open checklists.',
              body: _canManage
                  ? 'Tap Checklist to start one, or set up a template that creates them for you.'
                  : 'When your firm creates a checklist it shows up here.',
              onRetry: _loadAll,
              embedded: true,
            )
          else
            for (final r in shown)
              _RunCard(
                run: r,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChecklistRunScreen(workspace: widget.workspace, runId: r.id),
                  ));
                  _loadAll();
                },
              ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _templatesTab() {
    final list = _templates!;
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (list.isEmpty)
            _Empty(
              icon: Icons.event_repeat_outlined,
              title: 'No templates yet.',
              body: _canManage
                  ? 'A template creates the same checklist on a schedule, for example the monthly close. Tap Template to set one up.'
                  : 'Recurring schedules your firm sets up show up here.',
              onRetry: _loadAll,
              embedded: true,
            )
          else
            for (final t in list)
              _TemplateCard(
                template: t,
                onTap: () => _openTemplate(t),
              ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _openTemplate(RecurringChecklist t) async {
    final steps = await _service.loadTemplateSteps(t.id).catchError((_) => <String>[]);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _TemplateSheet(
        template: t,
        steps: steps,
        canManage: _canManage,
        service: _service,
        onChanged: _loadAll,
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  final ChecklistRun run;
  final VoidCallback onTap;
  const _RunCard({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
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
                    child: Text(run.title,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                  ),
                  if (run.fromTemplate)
                    Icon(Icons.event_repeat_outlined, size: 15, color: AppColors.inkSubtle),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.inkSubtle),
                ],
              ),
              if (run.clientName != null || run.runDate != null) ...[
                const SizedBox(height: 3),
                Text(
                  [
                    if (run.clientName != null) run.clientName!,
                    if (run.runDate != null) _day(run.runDate!),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: run.progress,
                  minHeight: 5,
                  backgroundColor: AppColors.surface2,
                  valueColor: AlwaysStoppedAnimation(
                      run.allDone || run.isCompleted ? AppColors.green : AppColors.primary),
                ),
              ),
              const SizedBox(height: 7),
              Text(runProgressLabel(run.totalItems, run.doneItems),
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final RecurringChecklist template;
  final VoidCallback onTap;
  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = template;
    final color = t.isActive
        ? AppColors.green
        : t.isPaused
            ? AppColors.amber
            : AppColors.inkSubtle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (t.clientName != null) t.clientName!,
                        templateScheduleLabel(
                            frequency: t.frequency, nextRun: t.nextRunDate, status: t.status),
                        '${t.stepCount} step${t.stepCount == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// A template's details and what can be done to it.
class _TemplateSheet extends StatefulWidget {
  final RecurringChecklist template;
  final List<String> steps;
  final bool canManage;
  final ChecklistService service;
  final Future<void> Function() onChanged;
  const _TemplateSheet({
    required this.template,
    required this.steps,
    required this.canManage,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this template?'),
        content: const Text('It stops creating checklists. Checklists it already made stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) await _run(() => widget.service.deleteTemplate(widget.template.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text(
                [
                  if (t.clientName != null) t.clientName!,
                  templateScheduleLabel(
                      frequency: t.frequency, nextRun: t.nextRunDate, status: t.status),
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'Created ${t.occurrencesGenerated} time${t.occurrencesGenerated == 1 ? '' : 's'}'
                '${t.maxOccurrences == null ? '' : ' of ${t.maxOccurrences}'}'
                '${t.endDate == null ? '' : ' · ends ${_day(t.endDate!)}'}',
                style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
              ),
              const SizedBox(height: 14),
              Text('STEPS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.inkSubtle)),
              const SizedBox(height: 6),
              if (widget.steps.isEmpty)
                Text('No steps.', style: TextStyle(fontSize: 13, color: AppColors.inkMuted))
              else
                for (var i = 0; i < widget.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${i + 1}. ${widget.steps[i]}',
                        style: TextStyle(fontSize: 13.5, color: AppColors.ink)),
                  ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(fontSize: 12.5, color: AppColors.red)),
              ],
              if (widget.canManage) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (t.isActive)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() => widget.service.setTemplateStatus(t.id, 'paused')),
                          icon: const Icon(Icons.pause_circle_outline, size: 18),
                          label: const Text('Pause'),
                        ),
                      ),
                    if (t.isPaused)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() => widget.service.setTemplateStatus(t.id, 'active')),
                          icon: const Icon(Icons.play_circle_outline, size: 18),
                          label: const Text('Resume'),
                        ),
                      ),
                    if (!t.isEnded) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() => widget.service.setTemplateStatus(t.id, 'ended')),
                          icon: const Icon(Icons.stop_circle_outlined, size: 18),
                          label: const Text('End'),
                        ),
                      ),
                    ],
                  ],
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: Icon(Icons.delete_outline, size: 17, color: AppColors.red),
                  label: Text('Delete template', style: TextStyle(color: AppColors.red)),
                ),
              ],
            ],
          ),
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
  final bool embedded;
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    required this.onRetry,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: AppColors.inkSubtle),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          if (!embedded) ...[
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
    return embedded ? content : Center(child: content);
  }
}
