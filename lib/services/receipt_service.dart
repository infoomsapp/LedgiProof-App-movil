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
}
