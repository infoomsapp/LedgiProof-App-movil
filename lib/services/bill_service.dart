import 'package:supabase_flutter/supabase_flutter.dart';

/// Vendor bills: what a firm owes its vendors and when. Mirrors the web's
/// bill.service.ts (same table, same statuses, same plan feature).
///
/// Every bill posts itself to the ledger on the server (bills_ledger.sql):
/// Dr expense / Cr Accounts Payable. "Mark paid" records a payment made
/// outside the app (Dr AP / Cr Bill Payments in Transit); the bank withdrawal
/// is then matched in Review. It does not move money. QuickBooks and Xero
/// draw the same line -- "Mark as paid" only records a payment made elsewhere,
/// and actually sending an ACH or a check is a separate, paid payments product
/// (QuickBooks Bill Pay, Xero + BILL) that needs a connected payment processor.
/// LedgiProof has none wired yet, so the phone says "record it here after you
/// pay" rather than pretend to send money.
class Vendor {
  final String id;
  final String name;
  Vendor.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        name = ((r['dba_name'] as String?)?.trim().isNotEmpty ?? false)
            ? r['dba_name'] as String
            : (r['legal_name'] as String?) ?? 'Vendor';
}

class VendorBill {
  final String id;
  final String vendorId;
  final String vendorName;
  final String? billNumber;
  final double amount;
  final DateTime dueDate;
  final String status; // pending | paid | overdue
  final DateTime? paidAt;
  final double? paidAmount;
  final String? notes;
  final DateTime billDate;

  /// 'manual' = marked paid here; 'bank' = paid straight from the bank feed.
  final String? paidVia;

  /// The bank withdrawal this payment is matched to, once it is.
  final String? transactionId;

  VendorBill.fromRow(Map<String, dynamic> r, Map<String, String> vendorNames)
      : id = r['id'] as String,
        vendorId = r['vendor_id'] as String,
        vendorName = vendorNames[r['vendor_id']] ?? 'Unknown vendor',
        billNumber = r['bill_number'] as String?,
        amount = (r['amount'] as num?)?.toDouble() ?? 0,
        dueDate = DateTime.tryParse((r['due_date'] as String?) ?? '') ??
            DateTime.now(),
        status = (r['status'] as String?) ?? 'pending',
        paidAt = r['paid_at'] == null
            ? null
            : DateTime.tryParse(r['paid_at'] as String),
        paidAmount = (r['paid_amount'] as num?)?.toDouble(),
        notes = r['notes'] as String?,
        billDate = DateTime.tryParse((r['bill_date'] as String?) ?? '') ??
            DateTime.now(),
        paidVia = r['paid_via'] as String?,
        transactionId = r['transaction_id'] as String?;

  bool get isPaid => status == 'paid';

  /// Paid here, waiting for its bank withdrawal to be matched in Review.
  bool get isInTransit => isPaid && transactionId == null && paidVia != 'bank';
}

class BillService {
  final _db = Supabase.instance.client;

  /// Roles the vendor_bills INSERT/UPDATE/DELETE policies accept. Checked
  /// before showing the entry point so the phone never offers a write RLS will
  /// reject; the policies remain the real gate.
  static const _roles = {'owner', 'admin', 'accountant'};
  static bool canManageBills(String role) => _roles.contains(role);

  /// Bill tracking is a Bookkeeper/Accountant plan feature -- of the
  /// WORKSPACE (its owner's plan), read from get_workspace_plan like the web.
  /// The server refuses bills on other plans (LB009) either way; when the
  /// plan can't be read the answer is "no" rather than a form that will fail.
  Future<bool> hasBillTracking(String orgId) async {
    try {
      final res = await _db.rpc('get_workspace_plan', params: {'p_org_id': orgId});
      final features = (res as Map)['features'] as Map?;
      final limit = (features?['bill_tracking'] as num?)?.toInt() ?? 0;
      return limit != 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<Vendor>> listVendors(String orgId) async {
    final rows = await _db
        .from('vendors')
        .select('id, legal_name, dba_name')
        .eq('org_id', orgId)
        .eq('is_active', true)
        .order('legal_name');
    return (rows as List)
        .map((r) => Vendor.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Quick-add a vendor by name so a bill can be entered without leaving the
  /// phone. Tax details (W-9, TIN) are completed later on the web.
  Future<Vendor> createVendor(String orgId, String name) async {
    final row = await _db
        .from('vendors')
        .insert({'org_id': orgId, 'legal_name': name.trim()})
        .select('id, legal_name, dba_name')
        .single();
    return Vendor.fromRow(Map<String, dynamic>.from(row));
  }

  Future<List<VendorBill>> listBills(String orgId) async {
    final results = await Future.wait([
      _db.from('vendor_bills').select().eq('org_id', orgId).order('due_date'),
      _db.from('vendors').select('id, legal_name, dba_name').eq('org_id', orgId),
    ]);
    final names = {
      for (final v in (results[1] as List))
        (v as Map)['id'] as String: Vendor.fromRow(Map<String, dynamic>.from(v)).name,
    };
    return (results[0] as List)
        .map((r) => VendorBill.fromRow(Map<String, dynamic>.from(r as Map), names))
        .toList();
  }

  Future<void> createBill({
    required String orgId,
    required String vendorId,
    required double amount,
    required DateTime dueDate,
    DateTime? billDate,
    String? billNumber,
    String? notes,
  }) async {
    if (amount <= 0) throw StateError('Enter an amount greater than zero.');
    await _db.from('vendor_bills').insert({
      'org_id': orgId,
      'vendor_id': vendorId,
      'amount': amount,
      'due_date': dueDate.toIso8601String().substring(0, 10),
      if (billDate != null) 'bill_date': billDate.toIso8601String().substring(0, 10),
      if ((billNumber ?? '').trim().isNotEmpty) 'bill_number': billNumber!.trim(),
      if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
    });
  }

  /// Records that the bill was paid (outside the app), for its full amount
  /// (partial payments aren't supported: LB004). Only a bill that is not
  /// already paid can be marked, so a double tap cannot overwrite the first
  /// record.
  Future<void> markPaid(String billId, {required DateTime date}) async {
    final updated = await _db
        .from('vendor_bills')
        .update({
          'status': 'paid',
          'paid_at': date.toUtc().toIso8601String(),
        })
        .eq('id', billId)
        .neq('status', 'paid')
        .select('id');
    if ((updated as List).isEmpty) {
      throw StateError('This bill is already marked as paid.');
    }
  }

  /// Undo "Mark paid" -- refused once its bank withdrawal is matched (LB006).
  Future<void> markUnpaid(VendorBill bill) async {
    final today = DateTime.now();
    final overdue = bill.dueDate.isBefore(DateTime(today.year, today.month, today.day));
    await _db
        .from('vendor_bills')
        .update({'status': overdue ? 'overdue' : 'pending'})
        .eq('id', bill.id);
  }

  Future<void> deleteBill(String billId) async {
    await _db.from('vendor_bills').delete().eq('id', billId);
  }
}
