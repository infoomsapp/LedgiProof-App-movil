import 'package:flutter/material.dart';
import '../services/manual_transaction_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

/// Mirrors src/components/transactions/NewTransactionDialog.tsx field-for-
/// field: Type (Expense/Income), Amount, Description, Date -- no vendor or
/// category fields, because the real create-transaction pipeline doesn't
/// collect those at manual-entry time either (see manual_transaction_service.dart).
class ManualExpenseScreen extends StatefulWidget {
  final Workspace workspace;
  const ManualExpenseScreen({super.key, required this.workspace});

  @override
  State<ManualExpenseScreen> createState() => _ManualExpenseScreenState();
}

class _ManualExpenseScreenState extends State<ManualExpenseScreen> {
  final _service = ManualTransactionService();
  final _amountCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  bool _isExpense = true;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final magnitude = double.tryParse(_amountCtrl.text);
    if (magnitude == null || magnitude <= 0) {
      setState(() => _error = 'Enter an amount greater than 0.');
      return;
    }
    if (_descriptionCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter a description.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.createTransaction(
        orgId: widget.workspace.orgId,
        isExpense: _isExpense,
        magnitude: magnitude,
        description: _descriptionCtrl.text.trim(),
        date: _date.toIso8601String().substring(0, 10),
        // Real bug found in the mobile audit: this never passed a clientId,
        // so a portal-client's expense always hit create-transaction with
        // client_id: null -- which failed authorization entirely (the edge
        // function only checked organization_memberships, a portal client
        // never has one). Null stays correct for a genuine personal/solo
        // workspace, which has no client to scope to.
        clientId: widget.workspace.portalClientId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_isExpense ? "Expense" : "Income"} added')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Was a fixed string regardless of cause, which hid every real
        // failure behind the same guess about membership. friendlyError
        // still redacts anything database-shaped.
        _error = friendlyError(e, 'Could not save the transaction.');
        _saving = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _date,
      firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New transaction', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Type', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _typeChip('Expense', true)),
                const SizedBox(width: 8),
                Expanded(child: _typeChip('Income', false)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Amount', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: TextStyle(color: AppColors.ink),
              decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Description', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _descriptionCtrl,
              style: TextStyle(color: AppColors.ink),
              decoration: const InputDecoration(hintText: 'e.g. Office supplies from Staples', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Date', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    style: TextStyle(color: AppColors.ink)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12.5)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add transaction', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String label, bool expense) {
    final selected = _isExpense == expense;
    final color = expense ? AppColors.red : AppColors.green;
    final bg = expense ? AppColors.redBg : AppColors.greenBg;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _isExpense = expense),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? bg : AppColors.surface,
          border: Border.all(color: selected ? color : AppColors.border, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? color : AppColors.inkMuted)),
      ),
    );
  }
}
