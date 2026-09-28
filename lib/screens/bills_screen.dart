import 'package:flutter/material.dart';
import '../services/bill_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/bill_status.dart';
import '../utils/errors.dart';
import '../utils/invoice_status.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)}';

String _date(DateTime d) => d.toIso8601String().substring(0, 10);

/// Vendor bills on the phone: what is owed, what is late, what is due this
/// week, and a one-tap "Mark as paid" once the payment was made. Same table
/// and plan feature as the web's Bills tab.
///
/// It does not send money: paying the vendor still happens at the bank (ACH,
/// check, wire), and this records that it happened -- the same "Mark as paid"
/// QuickBooks and Xero offer. The banner says so up front.
class BillsScreen extends StatefulWidget {
  final Workspace workspace;
  const BillsScreen({super.key, required this.workspace});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final _service = BillService();
  List<VendorBill>? _bills; // last good list: never blanked by a reload
  bool? _allowed; // null = still checking the plan
  bool _loading = true;
  Object? _error;
  bool _showPaid = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _service.hasBillTracking(widget.workspace.orgId);
    if (!mounted) return;
    setState(() => _allowed = ok);
    if (ok) await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bills = await _service.listBills(widget.workspace.orgId);
      if (!mounted) return;
      setState(() {
        _bills = bills;
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

  Future<void> _addBill() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _AddBillSheet(orgId: widget.workspace.orgId),
    );
    if (added == true) {
      _snack('Bill added.');
      _load();
    }
  }

  Future<void> _open(VendorBill bill) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _BillSheet(bill: bill),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _body(),
      floatingActionButton: (_allowed == true &&
              BillService.canManageBills(widget.workspace.role))
          ? FloatingActionButton.extended(
              onPressed: _addBill,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Bill'),
            )
          : null,
    );
  }

  Widget _body() {
    if (_allowed == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_allowed == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 30, color: AppColors.inkSubtle),
              const SizedBox(height: 12),
              Text('Bill tracking is not part of this plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 6),
              Text(
                'Track what you owe vendors and when it is due on the '
                'Bookkeeper and Accountant plans.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    final bills = _bills;
    if (bills == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 30, color: AppColors.red),
            const SizedBox(height: 10),
            Text('Could not load bills.',
                style: TextStyle(color: AppColors.ink)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final totals = summarizeBills(
      bills.map((b) => (status: b.status, dueDate: b.dueDate, amount: b.amount)),
    );
    final shown = bills.where((b) => b.isPaid == _showPaid).toList()
      ..sort((a, b) => _showPaid
          ? (b.paidAt ?? b.dueDate).compareTo(a.paidAt ?? a.dueDate)
          : a.dueDate.compareTo(b.dueDate));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: _Tile(
                    label: 'To pay',
                    value: _money(totals.toPay),
                    color: AppColors.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  label: 'Overdue',
                  value: _money(totals.overdue),
                  color: totals.overdue > 0 ? AppColors.red : AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  label: 'Due this week',
                  value: _money(totals.dueSoon),
                  color:
                      totals.dueSoon > 0 ? AppColors.amber : AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pay your vendor from your bank, then tap Mark as paid to '
                    'record it here. LedgiProof tracks and reminds; it does '
                    'not send money yet.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('To pay')),
              ButtonSegment(value: true, label: Text('Paid')),
            ],
            selected: {_showPaid},
            onSelectionChanged: (s) => setState(() => _showPaid = s.first),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Could not refresh. Showing what was loaded.',
                  style: TextStyle(fontSize: 12, color: AppColors.amber)),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _showPaid ? 'No paid bills yet' : 'Nothing to pay. All caught up.',
                  style: TextStyle(color: AppColors.inkMuted),
                ),
              ),
            )
          else
            for (final b in shown) _BillRow(bill: b, onTap: () => _open(b)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Tile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
}

Color _urgencyColor(BillUrgency u) => switch (u) {
      BillUrgency.overdue => AppColors.red,
      BillUrgency.dueSoon => AppColors.amber,
      BillUrgency.paid => AppColors.green,
      BillUrgency.upcoming => AppColors.inkMuted,
    };

class _BillRow extends StatelessWidget {
  final VendorBill bill;
  final VoidCallback onTap;
  const _BillRow({required this.bill, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final u = billUrgency(status: bill.status, dueDate: bill.dueDate);
    final label = billDueLabel(status: bill.status, dueDate: bill.dueDate);
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
                    Text(bill.vendorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Text(
                      '${bill.billNumber == null ? '' : '#${bill.billNumber} · '}$label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: _urgencyColor(u)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(_money(bill.isPaid ? (bill.paidAmount ?? bill.amount) : bill.amount),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bill: its details and the two things you can do to it.
class _BillSheet extends StatefulWidget {
  final VendorBill bill;
  const _BillSheet({required this.bill});

  @override
  State<_BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends State<_BillSheet> {
  final _service = BillService();
  DateTime _paidOn = DateTime.now();
  bool _busy = false;
  String? _error;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _paidOn = d);
  }

  Future<void> _markPaid() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.markPaid(widget.bill.id, date: _paidOn);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _markUnpaid() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.markUnpaid(widget.bill);
      if (mounted) Navigator.of(context).pop(true);
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
        title: const Text('Remove this bill?'),
        content: const Text('It will no longer be tracked.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Remove', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _service.deleteBill(widget.bill.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final u = billUrgency(status: b.status, dueDate: b.dueDate);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(b.vendorName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 2),
            Text(
              '${b.billNumber == null ? '' : 'Bill #${b.billNumber} · '}'
              '${billDueLabel(status: b.status, dueDate: b.dueDate)} '
              '(${_date(b.dueDate)})',
              style: TextStyle(fontSize: 12.5, color: _urgencyColor(u)),
            ),
            const SizedBox(height: 10),
            Text(_money(b.amount),
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            if ((b.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(b.notes!,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            ],
            const SizedBox(height: 16),
            if (b.isPaid) ...[
              Text(
                'Paid ${_money(b.paidAmount ?? b.amount)}'
                '${b.paidAt == null ? '' : ' on ${_date(b.paidAt!.toLocal())}'}.',
                style: TextStyle(fontSize: 13, color: AppColors.green),
              ),
              const SizedBox(height: 4),
              Text(
                b.isInTransit
                    ? 'Waiting for the bank withdrawal — it will be suggested in Review.'
                    : 'Matched to the bank withdrawal.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(fontSize: 12.5, color: AppColors.red)),
              ],
              if (b.isInTransit) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _markUnpaid,
                  child: const Text('Mark unpaid'),
                ),
              ],
            ]
            else ...[
              Text('Already paid it? Record the full amount here.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Paid on'),
                  child: Text(_date(_paidOn)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(fontSize: 12.5, color: AppColors.red)),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _markPaid,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark as paid',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(height: 4),
            // A paid bill is in the books twice over (bill + payment): it
            // can't be removed (LB007), only marked unpaid first.
            if (!b.isPaid)
              TextButton.icon(
                onPressed: _busy ? null : _delete,
                icon: Icon(Icons.delete_outline, size: 17, color: AppColors.red),
                label: Text('Remove bill', style: TextStyle(color: AppColors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Enter a bill: pick (or quick-add) the vendor, amount, due date. Same
/// fields as the web's Add bill form plus payment terms.
class _AddBillSheet extends StatefulWidget {
  final String orgId;
  const _AddBillSheet({required this.orgId});

  @override
  State<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<_AddBillSheet> {
  final _service = BillService();
  final _amount = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _newVendor = TextEditingController();
  List<Vendor>? _vendors;
  String? _vendorId;
  bool _addingVendor = false;
  DateTime _billDate = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  DueTerms? _terms = DueTerms.net30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.listVendors(widget.orgId).then((v) {
      if (!mounted) return;
      setState(() {
        _vendors = v;
        _addingVendor = v.isEmpty; // nothing to pick from: ask for a name
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendlyError(e));
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _number.dispose();
    _notes.dispose();
    _newVendor.dispose();
    super.dispose();
  }

  Future<void> _pickBillDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() {
        _billDate = d;
        if (_terms != null) _due = _terms!.dueFrom(d);
      });
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) {
      setState(() {
        _due = d;
        _terms = null;
      });
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_addingVendor ? _newVendor.text.trim().isEmpty : _vendorId == null) {
      setState(() => _error = 'Choose or add the vendor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var vendorId = _vendorId;
      if (_addingVendor) {
        vendorId = (await _service.createVendor(widget.orgId, _newVendor.text)).id;
      }
      await _service.createBill(
        orgId: widget.orgId,
        vendorId: vendorId!,
        amount: amount,
        dueDate: _due,
        billDate: _billDate,
        billNumber: _number.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _vendors;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a bill',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 14),
            if (vendors == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_addingVendor)
              TextField(
                controller: _newVendor,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'New vendor name',
                  suffixIcon: (vendors ?? []).isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Pick an existing vendor',
                          onPressed: () => setState(() => _addingVendor = false),
                        ),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _vendorId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vendor'),
                items: [
                  for (final v in vendors ?? const <Vendor>[])
                    DropdownMenuItem(value: v.id, child: Text(v.name)),
                ],
                onChanged: (v) => setState(() => _vendorId = v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _addingVendor = true),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New vendor'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              decoration:
                  const InputDecoration(labelText: 'Bill number (optional)'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickBillDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Bill date'),
                child: Text(_date(_billDate)),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDue,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Due'),
                child: Text(_date(_due)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in DueTerms.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t.label),
                        selected: _terms == t,
                        onSelected: (_) => setState(() {
                          _terms = t;
                          _due = t.dueFrom(_billDate);
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(fontSize: 12.5, color: AppColors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save bill',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
