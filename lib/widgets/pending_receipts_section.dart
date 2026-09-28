import 'package:flutter/material.dart';
import '../services/receipt_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import 'receipt_edit_sheet.dart';

/// "Receipts waiting for a match" -- the top of the Review tab, same as the
/// web's src/components/review/PendingReceipts.tsx. Every scanned receipt
/// match_receipt() couldn't link by itself stays here until it's resolved:
///   · "This one"       link_receipt() to a likely bank transaction
///   · "Fix"            correct what OCR read; match_receipt() runs again
///   · "Cash expense"   create_expense_from_receipt(): the receipt becomes
///                      the transaction (it then appears in the inbox)
///   · "Not needed"     dismiss_receipt()
/// Fixing and linking are open to whoever may act for the workspace (a
/// portal client too); recording and dismissing are staff-only ([canWrite]).
class PendingReceiptsSection extends StatefulWidget {
  final String orgId;
  final String? clientId;
  final bool canWrite;

  /// Bump to reload (pull-to-refresh, scope change).
  final int refreshToken;

  /// A receipt became a transaction: the review queue should reload.
  final VoidCallback? onExpenseCreated;

  const PendingReceiptsSection({
    super.key,
    required this.orgId,
    required this.clientId,
    required this.canWrite,
    this.refreshToken = 0,
    this.onExpenseCreated,
  });

  @override
  State<PendingReceiptsSection> createState() => _PendingReceiptsSectionState();
}

class _PendingReceiptsSectionState extends State<PendingReceiptsSection> {
  final _service = ReceiptService();
  List<PendingReceipt> _items = [];
  String? _busy;
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PendingReceiptsSection old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken || old.clientId != widget.clientId || old.orgId != widget.orgId) {
      _load();
    }
  }

  Future<void> _load() async {
    final clientId = widget.clientId;
    try {
      final items = await _service.getPending(widget.orgId, clientId);
      if (!mounted || clientId != widget.clientId) return;
      setState(() => _items = items);
    } catch (_) {
      // The inbox still works without this section; it just stays hidden.
      if (mounted) setState(() => _items = []);
    }
  }

  Future<void> _run(PendingReceipt r, Future<void> Function() fn) async {
    setState(() {
      _busy = r.id;
      _errors.remove(r.id);
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _errors[r.id] = friendlyError(e, 'Something went wrong with this receipt.'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _resolved(PendingReceipt r, String message) {
    setState(() => _items.removeWhere((x) => x.id == r.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _link(PendingReceipt r, MatchTx tx) => _run(r, () async {
        await _service.linkReceipt(documentId: r.id, transactionId: tx.id);
        if (mounted) _resolved(r, 'Linked to ${tx.description ?? 'the transaction'}');
      });

  Future<void> _fix(PendingReceipt r) async {
    final fields = await showReceiptEditSheet(context,
        merchant: r.merchant, amount: r.amount, date: r.date, currency: r.currency);
    if (fields == null || !mounted) return;
    await _run(r, () async {
      final m = await _service.correct(r.id, fields);
      if (!mounted) return;
      if (m.status == 'matched') {
        _resolved(r, 'Linked to ${m.transaction?.description ?? 'the transaction'}');
      } else {
        await _load();
        if (mounted && m.status == 'unmatched') {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Saved. No bank transaction matches yet.')));
        }
      }
    });
  }

  Future<void> _cash(PendingReceipt r) => _run(r, () async {
        await _service.createExpense(r.id);
        if (!mounted) return;
        _resolved(r, 'Expense recorded — categorize it below');
        widget.onExpenseCreated?.call();
      });

  Future<void> _dismiss(PendingReceipt r) => _run(r, () async {
        await _service.dismiss(r.id);
        if (mounted) _resolved(r, 'Receipt set aside');
      });

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Row(children: [
              Icon(Icons.receipt_long, size: 16, color: AppColors.cyan),
              const SizedBox(width: 6),
              Text('Receipts waiting for a match',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink)),
              const SizedBox(width: 6),
              Text('· ${_items.length}', style: TextStyle(fontSize: 12, color: AppColors.inkSubtle)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              widget.canWrite
                  ? 'Pick the right bank transaction, fix what was read, or record a cash purchase.'
                  : 'Pick the right bank transaction or fix what was read.',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted, height: 1.4),
            ),
          ),
          for (final r in _items) ...[_card(r), const SizedBox(height: 8)],
        ],
      ),
    );
  }

  Widget _card(PendingReceipt r) {
    final isBusy = _busy == r.id;
    final muted = TextStyle(fontSize: 11.5, color: AppColors.inkMuted);
    return Opacity(
      opacity: isBusy ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
              ),
              Text(r.amount != null ? formatMoney(r.amount!, r.currency) : '—',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
            ]),
            const SizedBox(height: 2),
            Text(
              r.matchStatus == 'no_amount' ? "${r.date ?? 'No date'} · couldn't read a total" : (r.date ?? 'No date'),
              style: TextStyle(fontSize: 11, color: r.matchStatus == 'no_amount' ? AppColors.amber : AppColors.inkSubtle),
            ),
            if (r.candidates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 2),
                decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Which bank transaction is it?',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.ink)),
                    for (final c in r.candidates)
                      Row(children: [
                        Expanded(
                          child: Text(
                            '${c.description ?? 'Transaction'} · ${formatMoney(c.amount, r.currency)} · ${c.transactionDate}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                        TextButton(onPressed: isBusy ? null : () => _link(r, c), child: const Text('This one')),
                      ]),
                  ],
                ),
              ),
            ],
            Wrap(
              spacing: 2,
              children: [
                TextButton.icon(
                  onPressed: isBusy ? null : () => _fix(r),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Fix'),
                ),
                if (widget.canWrite) ...[
                  TextButton.icon(
                    onPressed: isBusy || r.amount == null ? null : () => _confirmCash(r),
                    icon: const Icon(Icons.payments_outlined, size: 15),
                    label: const Text('Cash expense'),
                  ),
                  TextButton(
                    onPressed: isBusy ? null : () => _dismiss(r),
                    child: const Text('Not needed'),
                  ),
                ],
              ],
            ),
            if (_errors[r.id] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_errors[r.id]!, style: TextStyle(fontSize: 11.5, color: AppColors.red)),
              ),
          ],
        ),
      ),
    );
  }

  /// A cash expense adds a transaction to the books: say what it means first,
  /// so a card purchase that will arrive with the statement isn't doubled.
  Future<void> _confirmCash(PendingReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record as cash expense?'),
        content: Text(
          'Use this when ${r.label} was paid in cash or from an account you don\'t import. '
          'If it was paid by card or from your bank, wait for the statement instead — it links by itself.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Record expense'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _cash(r);
  }
}
