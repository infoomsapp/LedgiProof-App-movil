import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/invoice_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../utils/invoice_status.dart';
import 'invoice_compose_screen.dart';

part 'invoice_detail_parts.dart';

/// One invoice, and the button to pay it.
///
/// Until now the app could only list an invoice number, a status and a total.
/// Paying meant an accountant pasting a link into WhatsApp or email and the
/// client leaving the app to follow it. This closes that loop on the phone,
/// which is where a client actually reads the message telling them to pay.
class InvoiceDetailScreen extends StatefulWidget {
  final String invoiceId;

  /// Present when a staff member opened this. A draft is only sendable from
  /// here, and only by someone the invoices UPDATE policy would accept; a
  /// client of a firm never sees the action.
  final Workspace? workspace;

  const InvoiceDetailScreen(
      {super.key, required this.invoiceId, this.workspace});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _service = InvoiceService();
  late Future<InvoiceDetail> _future;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getDetail(widget.invoiceId);
  }

  void _reload() {
    setState(() {
      _future = _service.getDetail(widget.invoiceId);
    });
  }

  bool get _canSend {
    final w = widget.workspace;
    return w != null &&
        !w.isPortalClient &&
        InvoiceService.canCreateInvoices(w.role);
  }

  /// Sends a draft that already exists. Marking sent comes first and the email
  /// second, so a mail failure leaves the invoice sent and payable rather than
  /// rolling the whole thing back.
  Future<void> _send() async {
    if (_paying) return;
    setState(() => _paying = true);
    var emailed = true;
    try {
      await _service.markSent(widget.invoiceId);
      try {
        await _service.sendEmail(widget.invoiceId);
      } catch (_) {
        emailed = false;
      }
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emailed
              ? 'Invoice sent to your client.'
              : 'Invoice marked sent, but the email did not go out. '
                  'Share the pay link instead.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Staff on an invoice that has left draft: the actions a bookkeeper needs on
  /// the phone (record payment, remind, share, duplicate, void).
  bool _staffOn(InvoiceDetail inv) => _canSend && !inv.isDraft;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _recordPayment(InvoiceDetail inv) async {
    final result = await showModalBottomSheet<_PaymentInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _RecordPaymentSheet(
        balance: inv.balanceDue,
        currency: inv.currency,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _paying = true);
    try {
      await _service.recordPayment(
        invoiceId: inv.id,
        orgId: widget.workspace!.orgId,
        amount: result.amount,
        balanceDue: inv.balanceDue,
        date: result.date,
        method: result.method,
        reference: result.reference,
        notes: result.notes,
      );
      _snack('Payment recorded.');
      _reload();
    } catch (e) {
      _snack('Could not record the payment: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _remind(InvoiceDetail inv) async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      await _service.sendEmail(inv.id);
      _snack('Reminder sent to your client.');
      _reload();
    } catch (e) {
      _snack('Could not send the reminder: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Opens the system share sheet (WhatsApp, SMS, Messages, email...) with the
  /// pay link: how Xero shares an invoice from its phone app.
  Future<void> _shareLink(InvoiceDetail inv) async {
    final token = inv.publicToken;
    if (token == null) {
      _snack('This invoice has no link yet. Send it first.');
      return;
    }
    await Share.share(
      'Invoice ${inv.invoiceNumber} — ${_money(inv.balanceDue, inv.currency)} due: '
      '${InvoiceService.publicUrl(token)}',
      subject: 'Invoice ${inv.invoiceNumber}',
    );
  }

  Future<void> _copyLink(InvoiceDetail inv) async {
    final token = inv.publicToken;
    if (token == null) {
      _snack('This invoice has no link yet. Send it first.');
      return;
    }
    await Clipboard.setData(
        ClipboardData(text: InvoiceService.publicUrl(token)));
    _snack('Link copied.');
  }

  Future<void> _duplicate(InvoiceDetail inv) async {
    setState(() => _paying = true);
    try {
      final id = await _service.duplicate(inv, orgId: widget.workspace!.orgId);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            InvoiceDetailScreen(invoiceId: id, workspace: widget.workspace),
      ));
    } catch (e) {
      _snack('Could not duplicate: ${friendlyError(e)}');
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _void(InvoiceDetail inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Void invoice #${inv.invoiceNumber}?'),
        content: const Text(
            'It stops being payable and no longer counts as money owed. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Void', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _paying = true);
    try {
      await _service.voidInvoice(inv.id);
      _snack('Invoice voided.');
      _reload();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _edit(InvoiceDetail inv) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InvoiceComposeScreen(
        workspace: widget.workspace!,
        editing: inv,
      ),
    ));
    if (mounted) _reload();
  }

  Future<void> _pay(InvoiceDetail inv) async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final url = await _service.createCheckoutUrl(inv.publicToken!);
      if (!mounted) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start payment: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<InvoiceDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 30, color: AppColors.red),
                    const SizedBox(height: 12),
                    Text('Could not load this invoice.',
                        style: TextStyle(color: AppColors.ink)),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: _reload, child: const Text('Try again')),
                  ],
                ),
              ),
            );
          }

          final inv = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(inv: inv),
                const SizedBox(height: 18),
                if (inv.items.isNotEmpty) ...[
                  _SectionLabel('Items'),
                  _Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < inv.items.length; i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.border),
                          _ItemRow(item: inv.items[i], currency: inv.currency),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (inv.items.isNotEmpty) ...[
                  _TotalsCard(inv: inv),
                  const SizedBox(height: 18),
                ],
                if (inv.payments.isNotEmpty) ...[
                  _SectionLabel('Payments'),
                  _Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < inv.payments.length; i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.border),
                          _PaymentRow(
                              payment: inv.payments[i], currency: inv.currency),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                // Sent / viewed: what QuickBooks shows when you tap an invoice.
                // Staff only; a client does not need to see when they opened it.
                if (_canSend && (inv.sentAt != null || inv.viewedAt != null)) ...[
                  _SectionLabel('Activity'),
                  _Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (inv.sentAt != null)
                            _ActivityLine(
                              icon: Icons.send_outlined,
                              text: 'Sent ${_day(inv.sentAt!)}'
                                  '${inv.sentTo == null ? '' : ' to ${inv.sentTo}'}',
                            ),
                          if (inv.viewedAt != null)
                            _ActivityLine(
                              icon: Icons.visibility_outlined,
                              text: 'Viewed by your client ${_day(inv.viewedAt!)}',
                            )
                          else if (inv.sentAt != null)
                            _ActivityLine(
                              icon: Icons.visibility_off_outlined,
                              text: 'Not opened yet',
                              muted: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if ((inv.notes ?? '').trim().isNotEmpty) ...[
                  _SectionLabel('Notes'),
                  _Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(inv.notes!.trim(),
                          style: TextStyle(
                              fontSize: 13, color: AppColors.inkMuted)),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (inv.isVoid)
                  _Note(
                    icon: Icons.block,
                    color: AppColors.inkMuted,
                    text: 'This invoice is void. It cannot be paid.',
                  )
                else if (_staffOn(inv))
                  _StaffActions(
                    inv: inv,
                    busy: _paying,
                    onRecordPayment: () => _recordPayment(inv),
                    onRemind: () => _remind(inv),
                    onShare: () => _shareLink(inv),
                    onCopy: () => _copyLink(inv),
                    onDuplicate: () => _duplicate(inv),
                    onVoid: () => _void(inv),
                  )
                else
                  _PayArea(
                    inv: inv,
                    paying: _paying,
                    onPay: () => _pay(inv),
                    canSend: _canSend,
                    onSend: _send,
                    onEdit: () => _edit(inv),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _money(double v, String currency) =>
    '${currency == 'USD' ? '\$' : '$currency '}${v.toStringAsFixed(2)}';

class _Header extends StatelessWidget {
  final InvoiceDetail inv;
  const _Header({required this.inv});

  @override
  Widget build(BuildContext context) {
    final standing = invoiceStanding(
      status: inv.status,
      total: inv.total,
      balanceDue: inv.balanceDue,
      dueDate: inv.dueDate,
    );
    final overdue = standing.bucket == InvoiceBucket.overdue;
    final statusColor = standing.bucket == InvoiceBucket.paid
        ? AppColors.green
        : overdue
            ? AppColors.red
            : AppColors.inkMuted;
    final statusText = switch (standing.bucket) {
      InvoiceBucket.paid => 'Paid',
      InvoiceBucket.overdue => 'Overdue',
      InvoiceBucket.draft => 'Draft',
      InvoiceBucket.voided => 'Void',
      InvoiceBucket.awaiting => standing.partial ? 'Partly paid' : 'Sent',
    };

    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('#${inv.invoiceNumber}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: inv.isPaid
                        ? AppColors.greenBg
                        : overdue
                            ? AppColors.redBg
                            : AppColors.surface2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusText,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(_money(inv.balanceDue, inv.currency),
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 2),
            Text(
              inv.balanceDue == inv.total
                  ? 'Amount due'
                  : 'Due of ${_money(inv.total, inv.currency)}',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            if (inv.dueDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 15, color: statusColor),
                  const SizedBox(width: 7),
                  Text(
                    '${overdue ? 'Was due' : 'Due'} '
                    '${inv.dueDate!.toIso8601String().substring(0, 10)}'
                    '${standing.bucket == InvoiceBucket.awaiting || overdue ? ' · ${standing.label}' : ''}',
                    style: TextStyle(fontSize: 12.5, color: statusColor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PayArea extends StatelessWidget {
  final InvoiceDetail inv;
  final bool paying;
  final VoidCallback onPay;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onEdit;
  const _PayArea({
    required this.inv,
    required this.paying,
    required this.onPay,
    required this.canSend,
    required this.onSend,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (inv.isPaid) {
      return _Note(
        icon: Icons.check_circle_outline,
        color: AppColors.green,
        text: 'This invoice is paid. Nothing else to do.',
      );
    }
    if (inv.isDraft) {
      if (!canSend) {
        return _Note(
          icon: Icons.edit_outlined,
          color: AppColors.inkMuted,
          text: 'This invoice is still a draft and cannot be paid yet.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: paying ? null : onSend,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: paying
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
          const SizedBox(height: 6),
          // Editing is offered only while the invoice is still a draft, the
          // same rule the web applies: once it is sent the client is holding
          // that document.
          TextButton.icon(
            onPressed: paying ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Edit this draft'),
          ),
        ],
      );
    }
    if (inv.publicToken == null) {
      // Deliberately not attempting to mint the token here: the invoices
      // UPDATE policy requires an org role, which a portal client does not
      // have, so the write would be rejected and read as a broken button.
      return _Note(
        icon: Icons.link_off,
        color: AppColors.amber,
        text: 'This invoice has no payment link yet. Ask your accountant to '
            'send it, and it becomes payable here.',
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: paying ? null : onPay,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: paying
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text('Pay ${_money(inv.balanceDue, inv.currency)} securely',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Note({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InvoiceItem item;
  final String currency;
  const _ItemRow({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description,
                    style: TextStyle(fontSize: 13, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)}'
                  ' × ${_money(item.unitPrice, currency)}',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(_money(item.lineTotal, currency),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.inkSubtle,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
