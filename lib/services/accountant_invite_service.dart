import 'package:supabase_flutter/supabase_flutter.dart';

/// A solo/personal workspace has no chat and no way to grant real access to
/// anyone -- org membership is only ever created from a firm's side (see
/// AddClientDialog on the web). What this can honestly do is ask: create a
/// request row, then have the send-accountant-invite-request edge function
/// email the named accountant a link to set up their own firm and add this
/// person as a client through the real, existing invitation flow.
class AccountantInviteService {
  final _db = Supabase.instance.client;

  Future<void> requestAccountant({
    required String orgId,
    required String accountantEmail,
    String? accountantName,
    String? note,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('No session');

    final row = await _db
        .from('accountant_invite_requests')
        .insert({
          'org_id': orgId,
          'requested_by': userId,
          'accountant_email': accountantEmail,
          if (accountantName != null && accountantName.trim().isNotEmpty)
            'accountant_name': accountantName.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        })
        .select('id')
        .single();

    final requestId = row['id'] as String;

    await _db.functions.invoke(
      'send-accountant-invite-request',
      body: {'request_id': requestId},
    );
  }
}
