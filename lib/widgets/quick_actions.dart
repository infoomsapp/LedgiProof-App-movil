import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bill_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/quick_action_prefs.dart';
import 'capture_sheet.dart';

/// One card that can sit in the Home quick-actions row.
class QuickActionDef {
  final String id;
  final IconData icon;
  final String label;
  final String shortLabel;
  const QuickActionDef(this.id, this.icon, this.label, this.shortLabel);
}

/// Every card this workspace may put on Home: the Capture actions (with the
/// same per-workspace rule -- no mileage in a firm) plus two shortcuts that were
/// never on Home. Bills only for the firm staff the vendor_bills policies accept.
List<QuickActionDef> quickActionDefsFor(Workspace w) => [
      for (final a in captureActionsFor(w))
        QuickActionDef(a.id, a.icon, a.label, a.shortLabel),
      const QuickActionDef('invoices', Icons.request_page_outlined, 'Invoices', 'Invoices'),
      if (w.isFirm && !w.isPortalClient && BillService.canManageBills(w.role))
        const QuickActionDef('bills', Icons.request_quote_outlined, 'Bills', 'Bills'),
    ];

/// The Home "Quick actions" block: a row of up to five cards the person
/// chooses and orders with Edit. The choice is remembered on this phone, per
/// kind of workspace (a firm and a personal workspace offer different cards).
class QuickActionsSection extends StatefulWidget {
  final Workspace workspace;
  const QuickActionsSection({super.key, required this.workspace});

  @override
  State<QuickActionsSection> createState() => _QuickActionsSectionState();
}

class _QuickActionsSectionState extends State<QuickActionsSection> {
  List<String>? _saved; // null = nothing saved (or not loaded yet)

  String get _key => 'quick_actions_${widget.workspace.category.name}';
  List<QuickActionDef> get _defs => quickActionDefsFor(widget.workspace);
  List<String> get _available => _defs.map((d) => d.id).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant QuickActionsSection old) {
    super.didUpdateWidget(old);
    if (old.workspace.category != widget.workspace.category) _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key);
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      // Storage unavailable: the defaults are shown, nothing else is lost.
    }
  }

  Future<void> _store(List<String>? ids) async {
    setState(() => _saved = ids);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (ids == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setStringList(_key, ids);
      }
    } catch (_) {
      // Could not persist: it still applies for this session.
    }
  }

  Future<void> _edit() async {
    final chosen = resolveQuickActions(saved: _saved, available: _available);
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _EditSheet(defs: _defs, chosen: chosen),
    );
    if (result == null) return;
    await _store(result.reset ? null : result.ids);
  }

  @override
  Widget build(BuildContext context) {
    final defs = {for (final d in _defs) d.id: d};
    final ids = resolveQuickActions(saved: _saved, available: _available);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('QUICK ACTIONS',
                  style: TextStyle(
                      color: AppColors.inkSubtle,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
            TextButton.icon(
              onPressed: _edit,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.tune, size: 15),
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final id in ids)
              if (defs[id] != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => openQuickAction(context, id, widget.workspace),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Icon(defs[id]!.icon, size: 18, color: AppColors.primaryInk),
                            const SizedBox(height: 4),
                            Text(
                              defs[id]!.shortLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _EditResult {
  final List<String> ids;
  final bool reset;
  const _EditResult(this.ids, {this.reset = false});
}

/// Pick which cards show (up to five) and drag them into order.
class _EditSheet extends StatefulWidget {
  final List<QuickActionDef> defs;
  final List<String> chosen;
  const _EditSheet({required this.defs, required this.chosen});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final Map<String, QuickActionDef> _byId = {for (final d in widget.defs) d.id: d};
  late final List<String> _order = editListOrder(
    chosen: widget.chosen,
    available: widget.defs.map((d) => d.id).toList(),
  );
  late final Set<String> _selected = {...widget.chosen};

  void _toggle(String id, bool on) {
    if (on && _selected.length >= maxQuickActions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can keep up to 5 cards. Turn one off first.')),
      );
      return;
    }
    if (!on && _selected.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one card.')),
      );
      return;
    }
    setState(() => on ? _selected.add(id) : _selected.remove(id));
  }

  // onReorderItem already hands over the index AFTER the dragged item has been
  // removed, so no manual "-1" adjustment is needed here.
  void _reorder(int from, int to) {
    setState(() {
      final id = _order.removeAt(from);
      _order.insert(to, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit quick actions',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              'Choose up to 5 (${_selected.length} on) and drag to reorder.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: _reorder,
                itemBuilder: (context, i) {
                  final id = _order[i];
                  final d = _byId[id]!;
                  final on = _selected.contains(id);
                  return ListTile(
                    key: ValueKey(id),
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(value: on, onChanged: (v) => _toggle(id, v ?? false)),
                    title: Row(
                      children: [
                        Icon(d.icon, size: 18, color: on ? AppColors.primaryInk : AppColors.inkSubtle),
                        const SizedBox(width: 10),
                        Text(d.label,
                            style: TextStyle(
                                fontSize: 14,
                                color: on ? AppColors.ink : AppColors.inkMuted)),
                      ],
                    ),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_handle, color: AppColors.inkSubtle),
                    ),
                    onTap: () => _toggle(id, !on),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const _EditResult([], reset: true)),
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _EditResult([for (final id in _order) if (_selected.contains(id)) id]),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
