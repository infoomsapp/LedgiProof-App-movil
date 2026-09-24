import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Mirrors src/services/upload.service.ts's uploadDocument + register_document
/// RPC, and src/services/ocr.service.ts's extractReceiptOcr -- same bucket,
/// same storage path shape, same RPC, same edge function. No client-side
/// compression here (the web does browser-image-compression; skipped for
/// this first mobile pass, disclosed as a gap, not silently different).
class OcrResult {
  final String? merchantName;
  final double? totalAmount;
  final String? date;
  final String? category;
  final String currency;
  final int confidence;

  OcrResult.fromJson(Map<String, dynamic> json)
      : merchantName = json['merchant_name'] as String?,
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
}
