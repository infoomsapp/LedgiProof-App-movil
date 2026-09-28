import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/receipt_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../widgets/receipt_edit_sheet.dart';

enum _Stage { pick, uploading, extracting, done, error }

/// Camera -> real OCR -> result + bank match, exactly the contract
/// supabase/functions/ocr-receipt serves the web app: the receipt is a
/// registered, OCR'd document, and match_receipt() (run by the edge function)
/// links it to its bank transaction when there is a clear winner, offers the
/// likely candidates when there isn't, or leaves it waiting -- a statement
/// imported later links it by itself. It does not create a transaction.
class ReceiptCaptureScreen extends StatefulWidget {
  final Workspace workspace;
  /// Set in a firm workspace once a client has been chosen (see
  /// client_picker_sheet.dart) -- attributes the receipt to that client
  /// instead of leaving it as an unscoped org-level document. Null in a
  /// personal/portal-client workspace, which has no client to pick.
  final String? clientId;
  final String? clientName;
  const ReceiptCaptureScreen({super.key, required this.workspace, this.clientId, this.clientName});

  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  final _service = ReceiptService();
  final _picker = ImagePicker();

  _Stage _stage = _Stage.pick;
  String? _error;
  OcrResult? _result;
  String? _linkedId;
  String? _linking;
  bool _saving = false;

  // What the receipt reads -- OCR first, then whatever the user corrected --
  // and the latest match_receipt() decision for those values.
  String? _merchant;
  double? _amount;
  String? _date;
  String _currency = 'USD';
  ReceiptMatch? _match;

  Future<void> _capture(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2400);
    if (picked == null) return;

    setState(() {
      _stage = _Stage.uploading;
      _error = null;
    });

    try {
      final documentId = await _service.uploadReceipt(
        orgId: widget.workspace.orgId,
        file: File(picked.path),
        clientId: widget.clientId,
      );
      setState(() => _stage = _Stage.extracting);
      final result = await _service.extractOcr(documentId: documentId, orgId: widget.workspace.orgId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _merchant = result.merchantName;
        _amount = result.totalAmount;
        _date = result.date;
        _currency = result.currency.toUpperCase();
        _match = result.match;
        _stage = _Stage.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not process this receipt. It was still saved to your documents.';
        _stage = _Stage.error;
      });
    }
  }

  void _reset() => setState(() {
        _stage = _Stage.pick;
        _result = null;
        _error = null;
        _linkedId = null;
        _linking = null;
        _match = null;
      });

  /// "Fix what was read": save the corrected values and match again.
  Future<void> _edit() async {
    if (_linkedId != null || _match?.status == 'matched' || _saving) return;
    final fields = await showReceiptEditSheet(context,
        merchant: _merchant, amount: _amount, date: _date, currency: _currency);
    if (fields == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final m = await _service.correct(_result!.documentId, fields);
      if (!mounted) return;
      setState(() {
        _merchant = fields.merchant;
        _amount = fields.amount;
        _date = fields.date;
        _currency = fields.currency;
        _match = m;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, "Couldn't save the receipt."))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _link(MatchTx tx) async {
    setState(() => _linking = tx.id);
    try {
      await _service.linkReceipt(documentId: _result!.documentId, transactionId: tx.id);
      if (!mounted) return;
      setState(() => _linkedId = tx.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, "Couldn't link the receipt."))),
      );
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.clientName != null ? 'Scan receipt · ${widget.clientName}' : 'Scan receipt',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: switch (_stage) {
        _Stage.pick => _buildPick(),
        _Stage.uploading => _buildBusy('Uploading…'),
        _Stage.extracting => _buildBusy('Reading receipt…'),
        _Stage.done => _buildResult(),
        _Stage.error => _buildError(),
      },
    );
  }

  Widget _buildPick() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.inkSubtle),
          const SizedBox(height: 12),
          Text('Snap a photo of your receipt', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _capture(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take a photo'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _capture(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Choose from gallery'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusy(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(label, style: TextStyle(color: AppColors.inkMuted)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 32),
          const SizedBox(height: 10),
          Text(_error ?? 'Something went wrong.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink)),
          const SizedBox(height: 20),
          TextButton(onPressed: _reset, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final confColor = r.confidence >= 85 ? AppColors.green : (r.confidence >= 60 ? AppColors.amber : AppColors.red);
    final confBg = r.confidence >= 85 ? AppColors.greenBg : (r.confidence >= 60 ? AppColors.amberBg : AppColors.redBg);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.green, size: 20),
              const SizedBox(width: 8),
              Text('Receipt saved', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: confBg, borderRadius: BorderRadius.circular(100)),
                child: Text('${r.confidence}% confident', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: confColor)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_merchant == null && _amount == null && _date == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text("Couldn't read this one clearly — enter the total to match it with your bank.",
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
            ),
          _field('Merchant', _merchant ?? 'Tap to enter'),
          _field('Amount', _amount != null ? formatMoney(_amount!, _currency) : 'Tap to enter'),
          _field('Date', _date ?? 'Tap to enter'),
          if (r.category != null) _field('Category', r.category!.replaceAll('_', ' '), editable: false),
          if (_saving) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator()),
          const SizedBox(height: 8),
          if (_match != null) Flexible(child: SingleChildScrollView(child: _buildMatch(_match!))),
          const Spacer(),
          TextButton(onPressed: _reset, child: const Text('Scan another')),
        ],
      ),
    );
  }

  Widget _buildMatch(ReceiptMatch m) {
    Widget box(Color bg, Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
          child: child,
        );
    String line(MatchTx t) =>
        '${t.description ?? 'Transaction'} · ${formatMoney(t.amount, _currency)} · ${t.transactionDate}';
    final muted = TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4);

    switch (m.status) {
      case 'matched':
        return box(
          AppColors.cyanBg,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.link, size: 16, color: AppColors.cyan),
              const SizedBox(width: 6),
              Text('Matched to your bank transaction',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
            ]),
            if (m.transaction != null) ...[const SizedBox(height: 4), Text(line(m.transaction!), style: muted)],
          ]),
        );
      case 'suggested':
        return box(
          AppColors.amberBg,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Which bank transaction is this receipt for?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 6),
            for (final c in m.candidates)
              Row(children: [
                Expanded(child: Text(line(c), maxLines: 2, overflow: TextOverflow.ellipsis, style: muted)),
                if (_linkedId == c.id)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Text('Linked', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 12)),
                  )
                else
                  TextButton(
                    onPressed: _linking != null || _linkedId != null ? null : () => _link(c),
                    child: Text(_linking == c.id ? '…' : 'This one'),
                  ),
              ]),
          ]),
        );
      case 'no_amount':
        return box(AppColors.amberBg,
            Text("We couldn't read a total. Tap Amount to enter it and we'll look for the bank transaction.", style: muted));
      default:
        return box(
          AppColors.surface,
          Text(
            'No bank transaction matches yet — it will link by itself when the statement arrives. '
            'It waits in Review until then.',
            style: muted,
          ),
        );
    }
  }

  /// Tapping a field corrects what was read -- until the receipt is linked.
  Widget _field(String label, String value, {bool editable = true}) {
    final canEdit = editable && _linkedId == null && _match?.status != 'matched' && !_saving;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: canEdit ? _edit : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(9)),
          child: Row(
            children: [
              SizedBox(width: 80, child: Text(label.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.inkSubtle, letterSpacing: 0.4))),
              Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
              if (canEdit) Icon(Icons.edit_outlined, size: 15, color: AppColors.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
