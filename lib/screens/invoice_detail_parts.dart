part of 'invoice_detail_screen.dart';

String _day(DateTime t) {
  final l = t.toLocal();
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${m[l.month - 1]} ${l.day}, ${l.year}';
}

/// Subtotal / discount / tax / total / paid / balance -- the block a client
/// reads to check the maths. Rows only appear when they mean something.
class _TotalsCard extends StatelessWidget {
  final InvoiceDetail inv;
  const _TotalsCard({required this.inv});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool strong = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: strong ? 13.5 : 12.5,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                        color: color ?? AppColors.inkMuted)),
              ),
              Text(value,
                  style: TextStyle(
                      fontSize: strong ? 14 : 12.5,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                      color: color ?? AppColors.ink)),
            ],
          ),
        );
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            row('Subtotal', _money(inv.subtotal, inv.currency)),
            if (inv.discountTotal > 0)
              row('Discount', '−${_money(inv.discountTotal, inv.currency)}'),
            if (inv.taxTotal > 0) row('Tax', _money(inv.taxTotal, inv.currency)),
            Divider(height: 14, thickness: 1, color: AppColors.border),
            row('Total', _money(inv.total, inv.currency), strong: true),
            if (inv.amountPaid > 0) ...[
              row('Paid', '−${_money(inv.amountPaid, inv.currency)}',
                  color: AppColors.green),
              row('Balance due', _money(inv.balanceDue, inv.currency),
                  strong: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final InvoicePayment payment;
  final String currency;
  const _PaymentRow({required this.payment, required this.currency});

  @override
  Widget build(BuildContext context) {
    final method = paymentMethods[payment.method] ?? payment.method ?? 'Payment';
    final extra = [
      _day(payment.date),
      if ((payment.reference ?? '').isNotEmpty) 'Ref ${payment.reference}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(method,
                    style: TextStyle(fontSize: 13, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(extra,
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.inkSubtle)),
              ],
            ),
          ),
          Text(_money(payment.amount, currency),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.green)),
        ],
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;
  const _ActivityLine(
      {required this.icon, required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: muted ? AppColors.inkSubtle : AppColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: muted ? AppColors.inkSubtle : AppColors.inkMuted)),
            ),
          ],
        ),
      );
}

/// What a bookkeeper does with a sent invoice, in the order they reach for it.
class _StaffActions extends StatelessWidget {
  final InvoiceDetail inv;
  final bool busy;
  final VoidCallback onRecordPayment;
  final VoidCallback onRemind;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onDuplicate;
  final VoidCallback onVoid;
  const _StaffActions({
    required this.inv,
    required this.busy,
    required this.onRecordPayment,
    required this.onRemind,
    required this.onShare,
    required this.onCopy,
    required this.onDuplicate,
    required this.onVoid,
  });

  @override
  Widget build(BuildContext context) {
    final unpaid = !inv.isPaid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unpaid)
          FilledButton.icon(
            onPressed: busy ? null : onRecordPayment,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            icon: const Icon(Icons.payments_outlined, size: 19),
            label: const Text('Record payment',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          )
        else
          _Note(
            icon: Icons.check_circle_outline,
            color: AppColors.green,
            text: 'This invoice is paid. Nothing else to do.',
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (unpaid)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onRemind,
                  icon: const Icon(Icons.notifications_active_outlined,
                      size: 17),
                  label: const Text('Remind'),
                ),
              ),
            if (unpaid) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onShare,
                icon: const Icon(Icons.ios_share_outlined, size: 17),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onCopy,
                icon: const Icon(Icons.link, size: 17),
                label: const Text('Copy link'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: busy ? null : onDuplicate,
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('Duplicate'),
            ),
            if (unpaid && inv.amountPaid <= 0)
              TextButton.icon(
                onPressed: busy ? null : onVoid,
                icon: Icon(Icons.block, size: 16, color: AppColors.red),
                label: Text('Void', style: TextStyle(color: AppColors.red)),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaymentInput {
  final double amount;
  final DateTime date;
  final String method;
  final String? reference;
  final String? notes;
  const _PaymentInput(
      this.amount, this.date, this.method, this.reference, this.notes);
}

/// Bottom sheet to record a payment received outside the app. Defaults to the
/// full balance; type less for a partial payment.
class _RecordPaymentSheet extends StatefulWidget {
  final double balance;
  final String currency;
  const _RecordPaymentSheet({required this.balance, required this.currency});

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  late final _amount =
      TextEditingController(text: widget.balance.toStringAsFixed(2));
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = 'bank_transfer';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _date = d);
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (amount > widget.balance + 0.005) {
      setState(() => _error = 'That is more than the balance due.');
      return;
    }
    Navigator.of(context).pop(
        _PaymentInput(amount, _date, _method, _reference.text, _notes.text));
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Record payment',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 4),
            Text('Balance due ${_money(widget.balance, widget.currency)}',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount received',
                  helperText: 'Type less than the balance for a partial payment'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: [
                for (final e in paymentMethods.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date received'),
                child: Text(_date.toIso8601String().substring(0, 10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  helperText: 'Check number, transfer id...'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(fontSize: 12.5, color: AppColors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save payment',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
