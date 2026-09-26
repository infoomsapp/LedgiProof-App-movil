import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/invoice_service.dart';
import '../services/recurring_invoice_service.dart';
import '../services/sales_tax_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/doc_format.dart';
import '../utils/errors.dart';
import '../utils/invoice_status.dart';
import '../widgets/invoice_item_editor.dart';
import '../widgets/sales_tax_bar.dart';

/// Sets up an invoice that repeats: who, how often, from when, and what is on
/// it. The invoices themselves are made by the database on schedule (daily at
/// 6:00 UTC), numbered and totalled like any other invoice.
class RecurringInvoiceComposeScreen extends StatefulWidget {
  final Workspace workspace;
  const RecurringInvoiceComposeScreen({super.key, required this.workspace});

  @override
  State<RecurringInvoiceComposeScreen> createState() =>
      _RecurringInvoiceComposeScreenState();
}

class _RecurringInvoiceComposeScreenState
    extends State<RecurringInvoiceComposeScreen> {
  final _service = RecurringInvoiceService();
  final _books = BooksService();
  final _taxService = SalesTaxService();

  // Sales tax worked out from the client's state (see the invoice compose screen).
  SalesTaxSuggestion? _tax;
  bool _taxLoading = false;
  bool _taxApplied = false;
  int _taxEpoch = 0; // rebuilds the line fields when tax is written into them

  ClientSummary? _client;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  DateTime _start = _today();
  DueTerms _terms = DueTerms.net30;
  bool _autoSend = false;
  final _items = <DraftItem>[DraftItem()];
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTax() async {
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
    if (!mounted || _client?.id != c.id) return;
    setState(() {
      _tax = result;
      _taxLoading = false;
    });
    if (result.autoApply && result.rate != null) _applyTax();
  }

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

  int? get _max {
    final n = int.tryParse(_maxCtrl.text.trim());
    return n != null && n > 0 ? n : null;
  }

  double get _total =>
      _items.where((i) => i.isUsable).fold(0.0, (s, i) => s + i.lineTotal);

  bool get _canSave => _client != null && _items.any((i) => i.isUsable);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
                  children: [
                    for (final c in clients)
                      ListTile(
                        title: Text(c.displayName,
                            style: TextStyle(color: AppColors.ink)),
                        subtitle: c.companyName == null
                            ? null
                            : Text(c.companyName!,
                                style: TextStyle(color: AppColors.inkSubtle)),
                        onTap: () => Navigator.of(sheetContext).pop(c),
                      ),
                  ],
                ),
        ),
      );
      if (picked != null && mounted) {
        if (_taxApplied) _removeTax();
        setState(() => _client = picked);
        _loadTax();
      }
    } catch (e) {
      _snack('Could not load clients: ${friendlyError(e)}');
    }
  }

  Future<void> _pickStart() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(today) ? today : _start,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked != null && mounted) setState(() => _start = picked);
  }

  Future<void> _save() async {
    if (!_canSave || _busy) return;
    setState(() => _busy = true);
    try {
      if (_autoSend && !await _service.clientHasEmail(_client!.id)) {
        _snack('${_client!.displayName} has no email on file, so auto-send '
            'could not reach them. Add an email or turn auto-send off.');
        return;
      }
      await _service.create(
        orgId: widget.workspace.orgId,
        clientId: _client!.id,
        frequency: _frequency,
        startDate: _start,
        netDays: _terms.days,
        autoSend: _autoSend,
        items: _items,
        title: _titleCtrl.text,
        notes: _notesCtrl.text,
        maxOccurrences: _max,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Could not save: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.inkSubtle);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New recurring invoice',
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
          const SizedBox(height: 18),
          Text('REPEATS', style: label),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in RecurringFrequency.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _frequency == f,
                      onSelected:
                          _busy ? null : (_) => setState(() => _frequency = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            icon: Icons.event_outlined,
            label: 'First invoice',
            value: formatDocDate(_start),
            onTap: _busy ? null : _pickStart,
          ),
          const SizedBox(height: 12),
          Text('PAYMENT TERMS', style: label),
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
                      onSelected:
                          _busy ? null : (_) => setState(() => _terms = t),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SwitchListTile(
              value: _autoSend,
              onChanged: _busy ? null : (v) => setState(() => _autoSend = v),
              title: Text('Email it automatically',
                  style: TextStyle(fontSize: 13.5, color: AppColors.ink)),
              subtitle: Text(
                  _autoSend
                      ? 'Each invoice is sent to the client the morning it is created.'
                      : 'Each invoice is created as a draft for you to review and send.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
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
          Text('LINES', style: label),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            InvoiceItemEditor(
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text('Each invoice',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const Spacer(),
                Text(formatMoney(_total),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            style: TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(
                labelText: 'Title on the invoice (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(
                labelText: 'Notes for your client (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(
              labelText: 'Stop after this many invoices (optional)',
              helperText: 'Leave empty to repeat until you pause or delete it.',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (!_canSave || _busy) ? null : _save,
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
                : const Text('Start recurring invoice',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
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
              child: Text(value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: muted ? AppColors.inkSubtle : AppColors.ink)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: AppColors.inkSubtle),
          ],
        ),
      ),
    );
  }
}
