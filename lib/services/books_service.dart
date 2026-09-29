import 'package:supabase_flutter/supabase_flutter.dart';

class SemaphoreTx {
  final String id;
  final String? description;
  final String? merchantName;
  final double amount;
  final String semaphore; // blue / green / amber / red
  final DateTime txDate;

  SemaphoreTx.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        description = row['description'] as String?,
        merchantName = row['merchant_name'] as String?,
        amount = (row['amount'] as num).toDouble(),
        semaphore = row['semaphore'] as String,
        txDate = DateTime.parse(row['transaction_date'] as String);
}

class InvoiceSummary {
  final String id;
  final String invoiceNumber;
  final String status;
  final double total;
  final DateTime? dueDate;

  InvoiceSummary.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        invoiceNumber = (row['invoice_number'] as String?) ?? '—',
        status = (row['status'] as String?) ?? 'draft',
        total = (row['total'] as num?)?.toDouble() ?? 0,
        dueDate = row['due_date'] != null ? DateTime.parse(row['due_date'] as String) : null;
}

class ClientSummary {
  final String id;
  final String displayName;
  final String? companyName;

  ClientSummary.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        displayName = (row['display_name'] as String?) ?? 'Unnamed client',
        companyName = row['company_name'] as String?;
}

class BooksService {
  final _db = Supabase.instance.client;

  /// Transactions that need a look -- amber (not in the books yet, or
  /// flagged) or red (a problem), newest first. The colour is derived by the
  /// database (semaphore_v2.sql): blue verified by a person, green in the
  /// books and ready to verify, amber needs a look, red problem.
  /// This is the query behind Home's "N need your eyes" number and the
  /// Review tab's full queue; kept as one query so the two stay consistent.
  Future<List<SemaphoreTx>> getReviewQueue(String orgId, {int limit = 50}) async {
    final rows = await _db
        .from('transactions')
        .select('id, description, merchant_name, amount, semaphore, transaction_date')
        .eq('org_id', orgId)
        .eq('is_current', true)
        .inFilter('semaphore', ['amber', 'red'])
        .order('transaction_date', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => SemaphoreTx.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Verifies a transaction that is already in the books (green -> blue),
  /// through the same verify_transactions() the web uses. The database checks
  /// the role, refuses one that is not categorized yet (LV005), records who
  /// verified it and writes the audit entry. The colour is never written from
  /// here -- a direct UPDATE of `semaphore` would simply be recomputed.
  Future<void> verifyTransaction(String orgId, String transactionId) async {
    final data = await _db.rpc('verify_transactions', params: {
      'p_org_id': orgId,
      'p_transaction_ids': [transactionId],
    });
    final failed = ((data as Map?)?['failed'] as List?) ?? const [];
    if (failed.isNotEmpty) {
      final f = Map<String, dynamic>.from(failed.first as Map);
      throw StateError((f['error'] as String?) ?? 'Could not verify this transaction.');
    }
  }

  Future<List<InvoiceSummary>> getInvoices(String orgId, {int limit = 30}) async {
    final rows = await _db
        .from('invoices')
        .select('id, invoice_number, status, total, due_date')
        .eq('org_id', orgId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => InvoiceSummary.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<List<ClientSummary>> getClients(String orgId, {int limit = 50}) async {
    final rows = await _db
        .from('clients')
        .select('id, display_name, company_name')
        .eq('org_id', orgId)
        .eq('is_active', true)
        .order('display_name', ascending: true)
        .limit(limit);
    return (rows as List).map((r) => ClientSummary.fromRow(r as Map<String, dynamic>)).toList();
  }
}
