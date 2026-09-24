import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls supabase/functions/create-transaction -- the server-side port of
/// src/services/transactions.service.ts's createTransaction (hash-chain +
/// Brain rule evaluation + audit trail), so a transaction logged from mobile
/// gets exactly the same pipeline a transaction logged from the web does.
/// Mirrors NewTransactionDialog.tsx's contract exactly: type (expense/income)
/// -> signed amount, description, date. No vendor/category fields -- the
/// real product doesn't collect those at manual-entry time either.
class ManualTransactionService {
  final _db = Supabase.instance.client;

  Future<void> createTransaction({
    required String orgId,
    required bool isExpense,
    required double magnitude,
    required String description,
    required String date, // ISO 'YYYY-MM-DD'
    String? clientId,
  }) async {
    final res = await _db.functions.invoke('create-transaction', body: {
      'org_id': orgId,
      'client_id': clientId,
      'source': 'manual',
      'amount': isExpense ? -magnitude : magnitude,
      'description': description,
      'transaction_date': date,
    });
    final data = res.data;
    if (data is Map && data['error'] != null) {
      // StateError, not Exception: friendlyError() deliberately degrades an
      // unrecognised Exception to a generic message, which would throw away
      // the one string that says WHY this failed. The edge function already
      // ran it through safeMessage() server-side, so it is safe to show and
      // belongs in the trusted branch.
      throw StateError(data['error'] as String);
    }
  }
}
