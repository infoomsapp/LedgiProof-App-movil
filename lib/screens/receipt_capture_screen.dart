import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/receipt_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

enum _Stage { pick, uploading, extracting, done, error }

/// Camera -> real OCR -> result, exactly the contract
/// supabase/functions/ocr-receipt already serves the web app: this does NOT
/// create a transaction (the web app doesn't either -- a receipt is a
/// registered, OCR'd document; matching it to a transaction is a separate,
/// existing step). Showing anything more here would be simulating a "Save
/// expense" flow the real backend doesn't support yet.
class ReceiptCaptureScreen extends StatefulWidget {
  final Workspace workspace;
  const ReceiptCaptureScreen({super.key, required this.workspace});

  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  final _service = ReceiptService();
  final _picker = ImagePicker();

  _Stage _stage = _Stage.pick;
  String? _error;
  OcrResult? _result;

  Future<void> _capture(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2400);
    if (picked == null) return;

    setState(() {
      _stage = _Stage.uploading;
      _error = null;
    });

    try {
      final documentId = await _service.uploadReceipt(orgId: widget.workspace.orgId, file: File(picked.path));
      setState(() => _stage = _Stage.extracting);
      final result = await _service.extractOcr(documentId: documentId, orgId: widget.workspace.orgId);
      if (!mounted) return;
      setState(() {
        _result = result;
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
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
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
          if (!r.hasData)
            Text("Couldn't read this one clearly — it's saved to your documents for your bookkeeper to review.",
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13))
          else ...[
            _field('Merchant', r.merchantName ?? 'Tap to enter'),
            _field('Amount', r.totalAmount != null ? '${r.currency} ${r.totalAmount!.toStringAsFixed(2)}' : 'Tap to enter'),
            _field('Date', r.date ?? 'Tap to enter'),
            if (r.category != null) _field('Category', r.category!.replaceAll('_', ' ')),
          ],
          const SizedBox(height: 8),
          Text(
            'This receipt is stored and searchable in your documents. Matching it to a bank transaction happens from Review, same as the web app.',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle, height: 1.5),
          ),
          const Spacer(),
          TextButton(onPressed: _reset, child: const Text('Scan another')),
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(9)),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.inkSubtle, letterSpacing: 0.4))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
        ],
      ),
    );
  }
}
