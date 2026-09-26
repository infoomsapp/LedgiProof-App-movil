import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/invoice_service.dart';
import '../services/sales_tax_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../utils/invoice_status.dart';
import '../widgets/sales_tax_bar.dart';
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

  /// Set to edit an existing DRAFT instead of composing a new invoice.
  ///
  /// The client IS changeable here: snapshot_bill_to only freezes the client's
  /// billing details once the invoice stops being a draft, so a draft carries
  /// no snapshot for a reassignment to contradict. An earlier pass hid this
  /// field on the reasoning that moving a document between clients is not a
  /// correction -- true for an issued invoice, which cannot be edited at all,
  /// and wrong for a draft, where the wrong client is simply a mis-tap.
  final InvoiceDetail? editing;

  const InvoiceComposeScreen({
    super.key,
    required this.workspace,
    this.client,
    this.editing,
  });

  bool get isEditing => editing != null;

  @override
  State<InvoiceComposeScreen> createState() => _InvoiceComposeScreenState();
}

class _InvoiceComposeScreenState extends State<InvoiceComposeScreen> {
  final _service = InvoiceService();
  final _books = BooksService();
  final _taxService = SalesTaxService();

  // Sales tax worked out from the client's state, so it is never typed by hand.
  SalesTaxSuggestion? _tax;
  bool _taxLoading = false;
  bool _taxApplied = false;

  /// Bumped whenever tax is written into the lines, so their text fields are
  /// rebuilt (a TextFormField only reads its initial value once).
  int _taxEpoch = 0;

  ClientSummary? _client;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));

  /// The payment-terms chip that produced [_dueDate]; null once the date was
  /// picked by hand (or when editing a draft with its own date).
  DueTerms? _terms = DueTerms.net30;
  final _items = <DraftItem>[DraftItem()];
  final _notesCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    if (_client != null && widget.editing == null) _loadTax(allowAuto: true);

    final editing = widget.editing;
    if (editing != null) {
      // Stand-in so the row can show who it is for before any picker is
      // opened; replaced wholesale if the user picks somebody else.
      _client = ClientSummary.fromRow({
        'id': editing.clientId,
        'display_name': editing.clientName ?? 'Client',
      });
      if (editing.dueDate != null) {
        _dueDate = editing.dueDate!;
        _terms = null; // keep the draft's own date until the user picks terms
      }
      _notesCtrl.text = editing.notes ?? '';
      if (editing.items.isNotEmpty) {
        _items
          ..clear()
          ..addAll(editing.items.map((i) => DraftItem(
                description: i.description,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                discountPct: i.discountPct,
                taxRate: i.taxRate,
              )));
      }
      // A draft keeps the tax it was saved with; the suggestion is only offered.
      _loadTax(allowAuto: false);
    }
  }

  Future<void> _loadTax({required bool allowAuto}) async {
    final c = _client;
    if (c == null) return;
    setState(() {
      _taxLoading = true;
      _tax = null;
    });
    SalesTaxSuggestion result;
    try {
      result = await _taxService.suggestFor(
          orgId: widget.workspace.orgId, clientId: c.id);
    } catch (_) {
      result = const SalesTaxSuggestion(
          reason: 'Could not look up sales tax. You can still enter it by hand.');
    }
    // The person may have picked somebody else while this was loading.
    if (!mounted || _client?.id != c.id) return;
    setState(() {
      _tax = result;
      _taxLoading = false;
    });
    if (allowAuto && result.autoApply && result.rate != null) _applyTax();
  }

  /// Fills the tax on every line that has none; a line already taxed by hand
  /// is left alone.
  void _applyTax() {
    final r = _tax?.rate;
    if (r == null) return;
    setState(() {
      for (final i in _items) {
        if (i.taxRate == 0) i.taxRate = r.ratePct;
      }
      _taxApplied = true;
      _taxEpoch++;
    });
  }

  /// Turns on "add sales tax to every new invoice" for the firm, then applies
  /// it here too.
  Future<void> _alwaysAddTax() async {
    try {
      await _taxService.setCollectsSalesTax(widget.workspace.orgId, true);
      if (!mounted) return;
      final r = _tax?.rate;
      setState(() => _tax = SalesTaxSuggestion(rate: r, autoApply: true));
      _applyTax();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('New invoices will now include sales tax automatically. '
              'You can change this in Settings on the web.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: ${friendlyError(e)}')));
    }
  }

  void _removeTax() {
    final r = _tax?.rate;
    setState(() {
      for (final i in _items) {
        if (r != null && i.taxRate == r.ratePct) i.taxRate = 0;
      }
      _taxApplied = false;
      _taxEpoch++;
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total =>
      _items.where((i) => i.isUsable).fold(0.0, (sum, i) => sum + i.lineTotal);

  // When editing, the client is fixed and already on the invoice, so it is
  // not part of what makes the form valid.
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
      if (picked != null && mounted) {
        if (_taxApplied) _removeTax(); // the old client's rate must not linger
        setState(() => _client = picked);
        _loadTax(allowAuto: !widget.isEditing);
      }
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
    if (picked != null && mounted) {
      setState(() {
        _dueDate = picked;
        _terms = null;
      });
    }
  }

  /// [send] false keeps it a draft. True marks it sent and emails the client;
  /// the email is attempted after the invoice is already safely sent, so a
  /// mail failure never costs the invoice.
  Future<void> _save({required bool send}) async {
    if (!_canSave || _busy) return;
    setState(() => _busy = true);
    try {
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      final dueDate = _dueDate.toIso8601String().substring(0, 10);

      final String invoiceId;
      if (widget.isEditing) {
        invoiceId = widget.editing!.id;
        await _service.updateDraft(
          invoiceId: invoiceId,
          orgId: widget.workspace.orgId,
          dueDate: dueDate,
          items: _items,
          clientId: _client!.id,
          notes: notes,
        );
      } else {
        invoiceId = await _service.createDraft(
          orgId: widget.workspace.orgId,
          clientId: _client!.id,
          dueDate: dueDate,
          items: _items,
          notes: notes,
        );
      }

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
              ? (widget.isEditing ? 'Changes saved.' : 'Draft saved.')
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
        title: Text(
            widget.isEditing
                ? 'Edit invoice #${widget.editing!.invoiceNumber}'
                : 'New invoice',
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          const SizedBox(height: 8),
          // Payment terms: the one-tap due dates every invoicing app offers.
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
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                _terms = t;
                                _dueDate = t.dueFrom(DateTime.now());
                              }),
                    ),
                  ),
              ],
            ),
          ),
          SalesTaxBar(
            suggestion: _tax,
            loading: _taxLoading,
            applied: _taxApplied,
            onApply: _applyTax,
            onRemove: _removeTax,
            onAlways: _alwaysAddTax,
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
              key: ValueKey('${identityHashCode(_items[i])}-$_taxEpoch'),
              item: _items[i],
              onChanged: () => setState(() {}),
              onRemove: _items.length == 1
                  ? null
                  : () => setState(() => _items.removeAt(i)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() => _items.add(DraftItem(
                      taxRate:
                          _taxApplied ? (_tax?.rate?.ratePct ?? 0) : 0))),
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
                : Text(
                    widget.isEditing ? 'Save and send' : 'Send to client',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: (!_canSave || _busy) ? null : () => _save(send: false),
            child: Text(widget.isEditing ? 'Save changes' : 'Save as draft'),
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
          const SizedBox(height: 8),
          // Optional. Left at 0 the line keeps the database defaults, exactly
          // as on the web when these fields are not touched.
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.discountPct == 0
                      ? ''
                      : item.discountPct.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                      labelText: 'Discount %', isDense: true),
                  onChanged: (v) {
                    item.discountPct =
                        (double.tryParse(v) ?? 0).clamp(0, 100).toDouble();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue:
                      item.taxRate == 0 ? '' : item.taxRate.toString(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.ink, fontSize: 13.5),
                  decoration:
                      const InputDecoration(labelText: 'Tax %', isDense: true),
                  onChanged: (v) {
                    item.taxRate =
                        (double.tryParse(v) ?? 0).clamp(0, 100).toDouble();
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 84),
            ],
          ),
        ],
      ),
    );
  }
}
