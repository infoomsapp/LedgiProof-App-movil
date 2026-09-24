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

  /// Transactions that need a human decision -- amber or red, newest first.
  /// This is the query behind Home's "N need your eyes" number and the
  /// Review tab's full queue; kept as one query so the two stay consistent.
  Future<List<SemaphoreTx>> getReviewQueue(String orgId, {int limit = 50}) async {
    final rows = await _db
        .from('transactions')
        .select('id, description, merchant_name, amount, semaphore, transaction_date')
        .eq('org_id', orgId)
        .inFilter('semaphore', ['amber', 'red'])
        .order('transaction_date', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => SemaphoreTx.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Marks a transaction reviewed -- moves it to green, the same outcome
  /// approving it in the web app produces.
  Future<void> approveTransaction(String transactionId) async {
    await _db.from('transactions').update({'semaphore': 'green'}).eq('id', transactionId);
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

  Future<List<ClientSummary>> getClients(String orgId, {int limit = 50}) =>
      getClientsForOrgs([orgId], limit: limit);

  /// Clients across several workspaces.
  ///
  /// Needed because an accountant's clients live in their FIRM workspace while
  /// their own mileage is logged in their PERSONAL one: tagging which client a
  /// visit was for has to look outside the workspace the entry is being written
  /// to. RLS still applies per user, so this can only ever return clients of
  /// orgs the caller actually belongs to.
  Future<List<ClientSummary>> getClientsForOrgs(List<String> orgIds,
      {int limit = 50}) async {
    if (orgIds.isEmpty) return [];
    final rows = await _db
        .from('clients')
        .select('id, display_name, company_name')
        .inFilter('org_id', orgIds)
        .eq('is_active', true)
        .order('display_name', ascending: true)
        .limit(limit);
    return (rows as List).map((r) => ClientSummary.fromRow(r as Map<String, dynamic>)).toList();
  }
}
