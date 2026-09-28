import 'package:flutter/material.dart';
import '../services/receipt_service.dart';
import '../theme/app_theme.dart';

/// "Fix what was read": merchant, total, date and currency of a scanned
/// receipt. Pops the corrected [ReceiptFields], or null when cancelled. The
/// caller saves them with ReceiptService.correct(), which matches again.
Future<ReceiptFields?> showReceiptEditSheet(
  BuildContext context, {
  String? merchant,
  double? amount,
  String? date,
  String currency = 'USD',
}) {
  return showModalBottomSheet<ReceiptFields>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _ReceiptEditSheet(merchant: merchant, amount: amount, date: date, currency: currency),
  );
}

class _ReceiptEditSheet extends StatefulWidget {
  final String? merchant;
  final double? amount;
  final String? date;
  final String currency;
  const _ReceiptEditSheet({this.merchant, this.amount, this.date, required this.currency});

  @override
  State<_ReceiptEditSheet> createState() => _ReceiptEditSheetState();
}

class _ReceiptEditSheetState extends State<_ReceiptEditSheet> {
  late final _merchant = TextEditingController(text: widget.merchant ?? '');
  late final _amount = TextEditingController(text: widget.amount?.toStringAsFixed(2) ?? '');
  late final _currency = TextEditingController(text: widget.currency);
  late DateTime? _date = DateTime.tryParse(widget.date ?? '');
  String? _error;

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _currency.dispose();
    super.dispose();
  }

  String? get _isoDate => _date == null
      ? null
      : '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a total greater than zero');
      return;
    }
    final cur = _currency.text.trim().toUpperCase();
    Navigator.of(context).pop(ReceiptFields(
      merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
      amount: amount,
      date: _isoDate,
      currency: cur.length == 3 ? cur : 'USD',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(100))),
          ),
          const SizedBox(height: 14),
          Text('Fix what was read', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('Saving looks for the matching bank transaction again.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          const SizedBox(height: 14),
          TextField(
            controller: _merchant,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Merchant', isDense: true),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Total', isDense: true, errorText: _error),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _currency,
                  maxLength: 3,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Currency', isDense: true, counterText: ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_isoDate ?? 'Pick the date'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: BorderSide(color: AppColors.border),
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Save and match'),
          ),
        ],
      ),
    );
  }
}
