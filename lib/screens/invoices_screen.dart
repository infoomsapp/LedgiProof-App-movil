import 'package:flutter/material.dart';
import '../services/invoice_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/invoice_status.dart';
import 'invoice_compose_screen.dart';
import 'invoice_detail_screen.dart';

String _money(double v, String currency) =>
    '${currency == 'USD' ? '\$' : '$currency '}${v.toStringAsFixed(2)}';

enum _Filter { all, unpaid, overdue, paid, draft }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.unpaid => 'Unpaid',
        _Filter.overdue => 'Overdue',
        _Filter.paid => 'Paid',
        _Filter.draft => 'Drafts',
      };
}

/// Every invoice of a workspace on one screen, with the two numbers an
/// accountant looks at first (owed, overdue), filters, search and each
/// invoice's standing ("Overdue · 12 days", "Due in 5 days") right under its
/// client -- the QuickBooks / Xero mobile pattern. For a portal client the
/// same screen lists only their own invoices: the database narrows it.
class InvoicesScreen extends StatelessWidget {
  final Workspace workspace;
  const InvoicesScreen({super.key, required this.workspace});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: InvoicesBody(workspace: workspace),
      floatingActionButton: InvoiceNewButton(workspace: workspace),
    );
  }
}

/// The "+ Invoice" button, only for someone the invoices INSERT policy accepts
/// (owner/admin/accountant, never a portal client), so the phone never offers
/// a write the database would refuse.
class InvoiceNewButton extends StatelessWidget {
  final Workspace workspace;
  final VoidCallback? onDone;
  const InvoiceNewButton({super.key, required this.workspace, this.onDone});

  @override
  Widget build(BuildContext context) {
    if (workspace.isPortalClient ||
        !InvoiceService.canCreateInvoices(workspace.role)) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton.extended(
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvoiceComposeScreen(workspace: workspace),
        ));
        onDone?.call();
      },
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add, size: 20),
      label: const Text('Invoice'),
    );
  }
}

class InvoicesBody extends StatefulWidget {
  final Workspace workspace;
  const InvoicesBody({super.key, required this.workspace});

  @override
  State<InvoicesBody> createState() => _InvoicesBodyState();
}

class _InvoicesBodyState extends State<InvoicesBody> {
  final _service = InvoiceService();
  final _search = TextEditingController();
  List<InvoiceListItem>? _rows; // last good list: never blanked by a reload
  Object? _error;
  bool _loading = true;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _service.listInvoices(widget.workspace.orgId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  InvoiceStanding _standing(InvoiceListItem i) => invoiceStanding(
        status: i.status,
        total: i.total,
        balanceDue: i.balanceDue,
        dueDate: i.dueDate,
      );

  bool _matches(InvoiceListItem i) {
    final b = _standing(i).bucket;
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.unpaid =>
        b == InvoiceBucket.awaiting || b == InvoiceBucket.overdue,
      _Filter.overdue => b == InvoiceBucket.overdue,
      _Filter.paid => b == InvoiceBucket.paid,
      _Filter.draft => b == InvoiceBucket.draft,
    };
    if (!ok) return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return i.invoiceNumber.toLowerCase().contains(q) ||
        (i.clientName ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _ErrorState(onRetry: _load);
    }

    final totals = summarizeInvoices(
      rows.map((i) => (standing: _standing(i), balanceDue: i.balanceDue)),
    );
    final shown = rows.where(_matches).toList();
    final currency = rows.isEmpty ? 'USD' : rows.first.currency;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'Owed to you',
                  value: _money(totals.outstanding, currency),
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: totals.overdueCount == 0
                      ? 'Overdue'
                      : 'Overdue · ${totals.overdueCount}',
                  value: _money(totals.overdue, currency),
                  color: totals.overdue > 0 ? AppColors.red : AppColors.inkMuted,
                  onTap: totals.overdueCount == 0
                      ? null
                      : () => setState(() => _filter = _Filter.overdue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search number or client',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Could not refresh. Showing what was loaded.',
                  style: TextStyle(fontSize: 12, color: AppColors.amber)),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  rows.isEmpty ? 'No invoices yet' : 'Nothing matches',
                  style: TextStyle(color: AppColors.inkMuted),
                ),
              ),
            )
          else
            for (final inv in shown)
              _InvoiceRow(
                inv: inv,
                standing: _standing(inv),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => InvoiceDetailScreen(
                        invoiceId: inv.id, workspace: widget.workspace),
                  ));
                  if (mounted) _load();
                },
              ),
          const SizedBox(height: 80), // room for the floating button
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            Text(label,
                style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final InvoiceListItem inv;
  final InvoiceStanding standing;
  final VoidCallback onTap;
  const _InvoiceRow({
    required this.inv,
    required this.standing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (standing.bucket) {
      InvoiceBucket.overdue => AppColors.red,
      InvoiceBucket.paid => AppColors.green,
      InvoiceBucket.awaiting => standing.daysUntilDue <= 3
          ? AppColors.amber
          : AppColors.inkMuted,
      _ => AppColors.inkSubtle,
    };
    final showBalance = standing.bucket == InvoiceBucket.awaiting ||
        standing.bucket == InvoiceBucket.overdue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.clientName ?? 'Invoice #${inv.invoiceNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '#${inv.invoiceNumber} · ${standing.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(showBalance ? inv.balanceDue : inv.total, inv.currency),
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink),
                  ),
                  if (showBalance && inv.balanceDue < inv.total)
                    Text('of ${_money(inv.total, inv.currency)}',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.inkSubtle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 30, color: AppColors.red),
          const SizedBox(height: 10),
          Text('Could not load invoices.',
              style: TextStyle(color: AppColors.ink)),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
