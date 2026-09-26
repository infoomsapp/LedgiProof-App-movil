import 'package:flutter/material.dart';
import '../services/invoice_service.dart';
import '../services/recurring_invoice_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/doc_format.dart';
import '../utils/errors.dart';
import 'recurring_invoice_compose_screen.dart';

/// The app-bar button that opens this screen. Only for someone the recurring
/// tables' write policy accepts (owner/admin/accountant, never a portal
/// client), so the phone never offers what the database would refuse.
class RecurringInvoicesButton extends StatelessWidget {
  final Workspace workspace;
  const RecurringInvoicesButton({super.key, required this.workspace});

  @override
  Widget build(BuildContext context) {
    if (workspace.isPortalClient ||
        !InvoiceService.canCreateInvoices(workspace.role)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.autorenew),
      tooltip: 'Recurring invoices & reminders',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RecurringInvoicesScreen(workspace: workspace),
      )),
    );
  }
}

/// Invoices that repeat, plus the payment-reminder policy -- the two things
/// that send invoices to clients without anyone remembering to.
class RecurringInvoicesScreen extends StatefulWidget {
  final Workspace workspace;
  const RecurringInvoicesScreen({super.key, required this.workspace});

  @override
  State<RecurringInvoicesScreen> createState() =>
      _RecurringInvoicesScreenState();
}

class _RecurringInvoicesScreenState extends State<RecurringInvoicesScreen> {
  final _service = RecurringInvoiceService();
  List<RecurringInvoice>? _rows;
  ReminderPolicy? _policy;
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final org = widget.workspace.orgId;
      final results = await Future.wait([
        _service.list(org),
        _service.getReminderPolicy(org),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<RecurringInvoice>;
        _policy = results[1] as ReminderPolicy;
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

  /// Runs one write, then reloads. Every failure is shown, never swallowed.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) _snack(done);
      await _load();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _new() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecurringInvoiceComposeScreen(workspace: widget.workspace),
    ));
    if (created == true) {
      _snack('Recurring invoice created.');
      await _load();
    }
  }

  Future<void> _generateNow() => _run(() async {
        final n = await _service.generateDueNow(widget.workspace.orgId);
        _snack(n == 0
            ? 'Nothing is due yet.'
            : '$n invoice${n == 1 ? '' : 's'} created.');
      });

  Future<void> _toggle(RecurringInvoice r) => _run(
        () => _service.setStatus(
            r.id, r.isActive ? RecurringStatus.paused : RecurringStatus.active),
        done: r.isActive ? 'Paused.' : 'Resumed.',
      );

  Future<void> _delete(RecurringInvoice r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this recurring invoice?'),
        content: const Text(
            'No more invoices will be created from it. Invoices it already '
            'made are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _service.delete(r.id), done: 'Deleted.');
    }
  }

  Future<void> _editPolicy() async {
    final current = _policy ?? const ReminderPolicy();
    final result = await showModalBottomSheet<ReminderPolicy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _ReminderSheet(initial: current),
    );
    if (result == null) return;
    await _run(
      () => _service.saveReminderPolicy(widget.workspace.orgId, result),
      done: result.enabled ? 'Reminders are on.' : 'Reminders are off.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring & reminders',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          if (rows != null && rows.any((r) => r.isActive))
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Create what is due now',
              onPressed: _busy ? null : _generateNow,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _new,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Recurring'),
      ),
      body: rows == null
          ? (_loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 30, color: AppColors.red),
                      const SizedBox(height: 10),
                      Text('Could not load this.',
                          style: TextStyle(color: AppColors.ink)),
                      TextButton(onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _ReminderCard(
                    policy: _policy ?? const ReminderPolicy(),
                    onTap: _busy ? null : _editPolicy,
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('RECURRING INVOICES',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.inkSubtle)),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Could not refresh. Showing what was loaded.',
                          style: TextStyle(fontSize: 12, color: AppColors.amber)),
                    ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                            'Nothing repeats yet.\nSet up an invoice that bills '
                            'a client every week, month or year.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.inkMuted)),
                      ),
                    )
                  else
                    for (final r in rows)
                      _RecurringRow(
                        r: r,
                        onToggle: (_busy || r.status == RecurringStatus.ended)
                            ? null
                            : () => _toggle(r),
                        onDelete: _busy ? null : () => _delete(r),
                      ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final ReminderPolicy policy;
  final VoidCallback? onTap;
  const _ReminderCard({required this.policy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: policy.enabled ? AppColors.greenBg : AppColors.surface2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                  policy.enabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 19,
                  color: policy.enabled ? AppColors.green : AppColors.inkMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment reminders',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(
                      policy.enabled
                          ? 'On. ${policy.summary}'
                          : 'Off. Turn on to email clients before and after an invoice is due.',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSubtle),
          ],
        ),
      ),
    );
  }
}

class _RecurringRow extends StatelessWidget {
  final RecurringInvoice r;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;
  const _RecurringRow({required this.r, this.onToggle, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final (chipText, chipColor, chipBg) = switch (r.status) {
      RecurringStatus.active => ('Active', AppColors.green, AppColors.greenBg),
      RecurringStatus.paused => ('Paused', AppColors.amber, AppColors.amberBg),
      RecurringStatus.ended => ('Ended', AppColors.inkMuted, AppColors.surface2),
    };
    final title = r.title?.trim().isNotEmpty == true ? r.title! : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(r.clientName ?? 'Client',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: chipBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(chipText,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: chipColor)),
                    ),
                  ],
                ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  ),
                const SizedBox(height: 4),
                Text(r.scheduleLine,
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                Text(
                    [
                      r.autoSend ? 'Emailed automatically' : 'Created as draft',
                      if (r.progress.isNotEmpty) r.progress,
                    ].join(' · '),
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle)),
              ],
            ),
          ),
          Text(formatMoney(r.amount, currency: r.currency),
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppColors.inkSubtle),
            onSelected: (v) => v == 'toggle' ? onToggle?.call() : onDelete?.call(),
            itemBuilder: (_) => [
              if (onToggle != null)
                PopupMenuItem(
                    value: 'toggle',
                    child: Text(r.isActive ? 'Pause' : 'Resume')),
              PopupMenuItem(
                  value: 'delete',
                  enabled: onDelete != null,
                  child: Text('Delete', style: TextStyle(color: AppColors.red))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edit the reminder policy: a switch, "days before", "on the due date", and
/// the overdue milestones. Nothing is saved until Save is pressed.
class _ReminderSheet extends StatefulWidget {
  final ReminderPolicy initial;
  const _ReminderSheet({required this.initial});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late ReminderPolicy _p = widget.initial;

  static const _beforeChoices = [0, 1, 3, 5, 7];
  static const _overdueChoices = [1, 3, 5, 7, 14, 21, 30];

  void _toggleOverdue(int d) {
    final days = {..._p.overdueDays};
    if (!days.remove(d)) days.add(d);
    setState(() => _p = _p.copyWith(overdueDays: normalizeOverdueDays(days)));
  }

  @override
  Widget build(BuildContext context) {
    final sub = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.inkSubtle);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _p.enabled,
                onChanged: (v) => setState(() => _p = _p.copyWith(enabled: v)),
                title: Text('Email payment reminders',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink)),
                subtitle: Text(
                    'Sent each morning (Eastern time) to clients with an unpaid '
                    'invoice. Never twice for the same milestone.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: _p.enabled ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !_p.enabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BEFORE IT IS DUE', style: sub),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final d in _beforeChoices)
                            ChoiceChip(
                              label: Text(d == 0 ? 'None' : '$d day${d == 1 ? '' : 's'}'),
                              selected: _p.daysBefore == d,
                              onSelected: (_) =>
                                  setState(() => _p = _p.copyWith(daysBefore: d)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _p.onDue,
                        onChanged: (v) =>
                            setState(() => _p = _p.copyWith(onDue: v)),
                        title: Text('On the due date',
                            style: TextStyle(fontSize: 14, color: AppColors.ink)),
                      ),
                      const SizedBox(height: 4),
                      Text('AFTER IT IS DUE (DAYS LATE)', style: sub),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final d in _overdueChoices)
                            FilterChip(
                              label: Text('$d'),
                              selected: _p.overdueDays.contains(d),
                              onSelected: (_) => _toggleOverdue(d),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(_p.summary,
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_p),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save',
                      style:
                          TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
