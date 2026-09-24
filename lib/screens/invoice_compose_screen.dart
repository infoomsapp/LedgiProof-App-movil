import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/invoice_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import 'invoice_detail_screen.dart';

/// Compose an invoice on the phone: pick the client, set a due date, add
/// lines, then either keep it as a draft or send it.
///
/// Totals are shown from the numbers typed here, but the invoice that gets
/// stored is totalled by compute_invoice_totals on the server, exactly as the
/// web does it. The phone never writes a total.
class InvoiceComposeScreen extends StatefulWidget {
  final Workspace workspace;

  /// Pre-selected client, when composing from a client's own screen. Null in a
  /// firm workspace, where the first step is choosing who it is for.
  final ClientSummary? client;

  const InvoiceComposeScreen({super.key, required this.workspace, this.client});

  @override
  State<InvoiceComposeScreen> createState() => _InvoiceComposeScreenState();
}

class _InvoiceComposeScreenState extends State<InvoiceComposeScreen> {
  final _service = InvoiceService();
  final _books = BooksService();

  ClientSummary? _client;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  final _items = <DraftItem>[DraftItem()];
  final _notesCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total =>
      _items.where((i) => i.isUsable).fold(0.0, (sum, i) => sum + i.lineTotal);

  bool get _canSave => _client != null && _items.any((i) => i.isUsable);

  Future<void> _pickClient() async {
    try {
      final clients = await _books.getClients(widget.workspace.orgId);
      if (!mounted) return;
      final picked = await showModalBottomSheet<ClientSummary>(
        context: context,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: clients.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text('No clients in this workspace yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkMuted)),
                )
              : ListView(
                  shrinkWrap: true,
                  children: clients
                      .map((c) => ListTile(
                            title: Text(c.displayName,
                                style: TextStyle(color: AppColors.ink)),
                            subtitle: c.companyName == null
                                ? null
                                : Text(c.companyName!,
                                    style:
                                        TextStyle(color: AppColors.inkSubtle)),
                            onTap: () => Navigator.of(sheetContext).pop(c),
                          ))
                      .toList(),
                ),
        ),
      );
      if (picked != null && mounted) setState(() => _client = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load clients: ${friendlyError(e)}')),
      );
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  /// [send] false keeps it a draft. True marks it sent and emails the client;
  /// the email is attempted after the invoice is already safely sent, so a
  /// mail failure never costs the invoice.
  Future<void> _save({required bool send}) async {
    if (!_canSave || _busy) return;
    setState(() => _busy = true);
    try {
      final invoiceId = await _service.createDraft(
        orgId: widget.workspace.orgId,
        clientId: _client!.id,
        dueDate: _dueDate.toIso8601String().substring(0, 10),
        items: _items,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      var emailed = true;
      if (send) {
        await _service.markSent(invoiceId);
        try {
          await _service.sendEmail(invoiceId);
        } catch (_) {
          emailed = false;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
            invoiceId: invoiceId, workspace: widget.workspace),
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!send
              ? 'Draft saved.'
              : emailed
                  ? 'Invoice sent to your client.'
                  : 'Invoice marked sent, but the email did not go out. '
                      'Share the pay link instead.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New invoice',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Row(
            icon: Icons.person_outline,
            label: 'Client',
            value: _client?.displayName ?? 'Choose a client',
            muted: _client == null,
            onTap: _busy ? null : _pickClient,
          ),
          const SizedBox(height: 10),
          _Row(
            icon: Icons.event_outlined,
            label: 'Due',
            value: _dueDate.toIso8601String().substring(0, 10),
            onTap: _busy ? null : _pickDueDate,
          ),
          const SizedBox(height: 22),
          Text('LINES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.inkSubtle)),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            _ItemEditor(
              key: ValueKey(_items[i]),
              item: _items[i],
              onChanged: () => setState(() {}),
              onRemove: _items.length == 1
                  ? null
                  : () => setState(() => _items.removeAt(i)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  _busy ? null : () => setState(() => _items.add(DraftItem())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a line'),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text('Total',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const Spacer(),
                Text('\$${_total.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _notesCtrl,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(
                labelText: 'Notes for your client (optional)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (!_canSave || _busy) ? null : () => _save(send: true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send to client',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: (!_canSave || _busy) ? null : () => _save(send: false),
            child: const Text('Save as draft'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.inkMuted),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: muted ? AppColors.inkSubtle : AppColors.ink),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: AppColors.inkSubtle),
          ],
        ),
      ),
    );
  }
}

class _ItemEditor extends StatelessWidget {
  final DraftItem item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _ItemEditor({
    super.key,
    required this.item,
    required this.onChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.description,
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                      labelText: 'Description', isDense: true),
                  onChanged: (v) {
                    item.description = v;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.close,
                    size: 18,
                    color: onRemove == null
                        ? AppColors.border
                        : AppColors.inkSubtle),
                tooltip: 'Remove this line',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.quantity == 1
                      ? '1'
                      : item.quantity.toStringAsFixed(2),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration:
                      const InputDecoration(labelText: 'Qty', isDense: true),
                  onChanged: (v) {
                    item.quantity = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue:
                      item.unitPrice == 0 ? '' : item.unitPrice.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                      labelText: 'Unit price', isDense: true),
                  onChanged: (v) {
                    item.unitPrice = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 78,
                child: Text(
                  '\$${item.lineTotal.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ],
      ),
    );
  }
}
