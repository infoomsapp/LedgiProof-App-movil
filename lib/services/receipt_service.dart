import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Mirrors src/services/upload.service.ts's uploadDocument + register_document
/// RPC, and src/services/ocr.service.ts's extractReceiptOcr + linkReceipt --
/// same bucket, same storage path shape, same RPCs, same edge function. No
/// client-side compression here (the web does browser-image-compression;
/// skipped for this first mobile pass, disclosed as a gap, not silently
/// different).

/// A bank transaction the receipt was (or may be) matched to.
class MatchTx {
  final String id;
  final String? description;
  final double amount;
  final String transactionDate;

  MatchTx.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        description = j['description'] as String?,
        amount = (j['amount'] as num).toDouble(),
        transactionDate = j['transaction_date'] as String;
}

/// What match_receipt() decided right after OCR: 'matched' (linked to
/// [transaction]), 'suggested' (pick one of [candidates]), 'unmatched' (waits
/// for the statement import -- it links by itself then) or 'no_amount'.
class ReceiptMatch {
  final String status;
  final MatchTx? transaction;
  final List<MatchTx> candidates;

  ReceiptMatch.fromJson(Map<String, dynamic> j)
      : status = (j['status'] as String?) ?? 'unmatched',
        transaction = j['transaction'] is Map<String, dynamic>
            ? MatchTx.fromJson(j['transaction'] as Map<String, dynamic>)
            : null,
        candidates = ((j['candidates'] as List?) ?? [])
            .map((e) => MatchTx.fromJson(e as Map<String, dynamic>))
            .toList();
}

class OcrResult {
  final String documentId;
  /// Null when matching failed server-side; the OCR fields are still valid.
  final ReceiptMatch? match;
  final String? merchantName;
  final double? totalAmount;
  final String? date;
  final String? category;
  final String currency;
  final int confidence;

  OcrResult.fromJson(Map<String, dynamic> json)
      : documentId = json['document_id'] as String,
        match = json['match'] is Map<String, dynamic>
            ? ReceiptMatch.fromJson(json['match'] as Map<String, dynamic>)
            : null,
        merchantName = json['merchant_name'] as String?,
        totalAmount = (json['total_amount'] as num?)?.toDouble(),
        date = json['date'] as String?,
        category = json['category'] as String?,
        currency = (json['currency'] as String?) ?? 'USD',
        confidence = (json['confidence'] as num?)?.toInt() ?? 0;

  bool get hasData => merchantName != null || totalAmount != null || date != null;
}

/// '$12.50' for USD, 'EUR 12.50' otherwise -- same as the review inbox rows.
String formatMoney(double amount, String? currency) {
  final c = (currency ?? 'USD').toUpperCase();
  return '${c == 'USD' ? '\$' : '$c '}${amount.abs().toStringAsFixed(2)}';
}

/// What the user says the receipt reads (the OCR, corrected).
class ReceiptFields {
  final String? merchant;
  final double amount;
  final String? date; // YYYY-MM-DD
  final String currency;
  const ReceiptFields({this.merchant, required this.amount, this.date, this.currency = 'USD'});
}

/// A scanned receipt still waiting for its bank transaction
/// (get_pending_receipts).
class PendingReceipt {
  final String id;
  final String filename;
  final String matchStatus; // 'suggested' | 'unmatched' | 'no_amount'
  final String? merchant;
  final double? amount;
  final String? date;
  final String currency;
  final List<MatchTx> candidates;

  PendingReceipt.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        filename = (j['filename'] as String?) ?? 'Receipt',
        matchStatus = (j['match_status'] as String?) ?? 'unmatched',
        merchant = j['ocr_merchant'] as String?,
        amount = (j['ocr_amount'] as num?)?.toDouble(),
        date = j['ocr_date'] as String?,
        currency = ((j['ocr_currency'] as String?) ?? 'USD').toUpperCase(),
        candidates = ((j['candidates'] as List?) ?? [])
            .map((e) => MatchTx.fromJson(e as Map<String, dynamic>))
            .toList();

  String get label => merchant ?? filename;
}

class ReceiptService {
  static const _bucket = 'transaction-documents';
  final _db = Supabase.instance.client;
  final _uuid = const Uuid();

  Future<String> uploadReceipt({
    required String orgId,
    required File file,
    String? clientId,
  }) async {
    final filename = file.path.split(Platform.pathSeparator).last;
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = '$orgId/${clientId ?? 'org'}/general/${_uuid.v4()}_$safeName';
    final bytes = await file.readAsBytes();
    final mimeType = safeName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

    await _db.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, cacheControl: '3600', upsert: false),
        );

    try {
      final result = await _db.rpc('register_document', params: {
        'p_org_id': orgId,
        'p_storage_path': storagePath,
        'p_filename': filename,
        'p_mime_type': mimeType,
        'p_size_bytes': bytes.length,
        'p_client_id': clientId,
        'p_document_kind': 'receipt',
        'p_storage_bucket': _bucket,
      });
      return (result as Map<String, dynamic>)['document_id'] as String;
    } catch (e) {
      // Compensate the orphaned blob, same as the web service does on a
      // failed registration.
      await _db.storage.from(_bucket).remove([storagePath]).catchError((_) => <FileObject>[]);
      rethrow;
    }
  }

  Future<OcrResult> extractOcr({required String documentId, required String orgId}) async {
    final res = await _db.functions.invoke('ocr-receipt', body: {
      'document_id': documentId,
      'org_id': orgId,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error'] as String);
    return OcrResult.fromJson(data);
  }

  /// The user picked which bank transaction a suggested receipt belongs to.
  Future<void> linkReceipt({required String documentId, required String transactionId}) async {
    await _db.rpc('link_receipt', params: {
      'p_document_id': documentId,
      'p_transaction_id': transactionId,
    });
  }

  /// Receipts of this scope still waiting for their bank transaction.
  Future<List<PendingReceipt>> getPending(String orgId, String? clientId) async {
    final data = await _db.rpc('get_pending_receipts', params: {
      'p_org_id': orgId,
      'p_client_id': clientId,
    });
    return (((data as Map<String, dynamic>)['items'] as List?) ?? [])
        .map((e) => PendingReceipt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The user corrected what OCR read: store it and look for the bank line
  /// again -- match_receipt is the same RPC the edge function runs.
  Future<ReceiptMatch> correct(String documentId, ReceiptFields f) async {
    final data = await _db.rpc('match_receipt', params: {
      'p_document_id': documentId,
      'p_merchant': f.merchant ?? '',
      'p_amount': f.amount,
      'p_date': f.date,
      'p_currency': f.currency,
      'p_confidence': 100,
    });
    return ReceiptMatch.fromJson(data as Map<String, dynamic>);
  }

  /// Paid in cash / from an account that isn't imported: the receipt becomes
  /// the expense transaction, which then waits in "For review".
  Future<MatchTx> createExpense(String documentId) async {
    final data = await _db.rpc('create_expense_from_receipt', params: {'p_document_id': documentId});
    return MatchTx.fromJson((data as Map<String, dynamic>)['transaction'] as Map<String, dynamic>);
  }

  /// The receipt doesn't need a transaction.
  Future<void> dismiss(String documentId) async {
    await _db.rpc('dismiss_receipt', params: {'p_document_id': documentId});
  }
}
