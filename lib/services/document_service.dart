import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Mirrors src/services/upload.service.ts's list/view side (register_document
/// itself is already ported in receipt_service.dart's uploadReceipt). This
/// closes the gap ReceiptCaptureScreen's own result screen promises but the
/// app never delivered: "stored and searchable in your documents" had
/// nowhere for that search to actually happen on mobile.
class DocumentRow {
  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String documentKind;
  final String uploadedByRole;
  final DateTime createdAt;

  DocumentRow.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        filename = row['filename'] as String,
        mimeType = row['mime_type'] as String,
        sizeBytes = (row['size_bytes'] as num).toInt(),
        documentKind = (row['document_kind'] as String?) ?? 'attachment',
        uploadedByRole = (row['uploaded_by_role'] as String?) ?? 'bookkeeper',
        createdAt = DateTime.tryParse((row['created_at'] as String?) ?? '') ?? DateTime.now();

  bool get isImage => mimeType.startsWith('image/');
}

class SignedDocument {
  final String url;
  final String mimeType;
  final String filename;
  SignedDocument({required this.url, required this.mimeType, required this.filename});
}

class DocumentService {
  static const _bucket = 'transaction-documents';
  final _db = Supabase.instance.client;
  final _uuid = const Uuid();

  /// Uploads a file and registers it as a chat attachment, returning the
  /// document id to hand to send_workspace_message's p_document_id.
  ///
  /// Same bucket, same storage-path shape and same register_document RPC that
  /// receipt_service.uploadReceipt uses -- the only difference is
  /// document_kind 'attachment' instead of 'receipt', so an attachment does
  /// not turn up in the receipts flow. register_document itself authorises
  /// both a staff member and a portal client, which is why a client can
  /// attach a file back without anyone approving it first.
  Future<String> uploadAttachment({
    required String orgId,
    required File file,
    String? clientId,
  }) async {
    final filename = file.path.split(Platform.pathSeparator).last;
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        '$orgId/${clientId ?? 'org'}/chat/${_uuid.v4()}_$safeName';
    final bytes = await file.readAsBytes();
    final lower = safeName.toLowerCase();
    final mimeType = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.pdf')
            ? 'application/pdf'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';

    await _db.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
              contentType: mimeType, cacheControl: '3600', upsert: false),
        );

    try {
      final result = await _db.rpc('register_document', params: {
        'p_org_id': orgId,
        'p_storage_path': storagePath,
        'p_filename': filename,
        'p_mime_type': mimeType,
        'p_size_bytes': bytes.length,
        'p_client_id': clientId,
        'p_document_kind': 'attachment',
        'p_storage_bucket': _bucket,
      });
      return (result as Map<String, dynamic>)['document_id'] as String;
    } catch (e) {
      // Compensate the orphaned blob, same as the web and receipt_service do
      // when registration fails after the upload succeeded.
      await _db.storage
          .from(_bucket)
          .remove([storagePath]).catchError((_) => <FileObject>[]);
      rethrow;
    }
  }

  /// [clientId] null lists every document under the org (personal/portal-
  /// client workspaces, which only ever have one implicit "client"); set it
  /// to scope to one client's documents in a firm workspace.
  Future<List<DocumentRow>> list({required String orgId, String? clientId}) async {
    var query = _db
        .from('documents')
        .select('id, filename, mime_type, size_bytes, document_kind, uploaded_by_role, created_at')
        .eq('org_id', orgId)
        .isFilter('deleted_at', null);
    if (clientId != null) query = query.eq('client_id', clientId);
    final rows = await query.order('created_at', ascending: false);
    return (rows as List).map((r) => DocumentRow.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<SignedDocument> getSignedUrl(String documentId) async {
    final data = await _db.rpc('get_document_signed_url', params: {'p_document_id': documentId});
    final meta = Map<String, dynamic>.from(data as Map);
    final bucket = meta['storage_bucket'] as String;
    final path = meta['storage_path'] as String;
    final signed = await _db.storage.from(bucket).createSignedUrl(path, 3600);
    return SignedDocument(
      url: signed,
      mimeType: meta['mime_type'] as String,
      filename: meta['filename'] as String,
    );
  }
}
