import 'package:supabase_flutter/supabase_flutter.dart';

/// The mobile side of the client-portal invite flow -- the actual gap the
/// user flagged: the app had a Sign In screen and nothing else, so a client
/// invited to a firm's portal had no way to accept that invite from the
/// phone at all. Mirrors src/pages/ClientPortalActivatePage.tsx's contract
/// exactly: same RPCs, same auth metadata shape, so an account created here
/// looks identical to one created on the web.
class InvitationPreview {
  final String email;
  final String role; // client_owner | client_contact | client_viewer
  final String orgName;
  final String clientName;
  final String status; // pending | accepted | expired | revoked
  final DateTime expiresAt;

  InvitationPreview.fromJson(Map<String, dynamic> j)
      : email = j['email'] as String,
        role = j['role'] as String,
        orgName = (j['org_name'] as String?) ?? 'this workspace',
        clientName = (j['client_name'] as String?) ?? 'this client account',
        status = j['status'] as String,
        expiresAt = DateTime.parse(j['expires_at'] as String);

  bool get isUsable => status == 'pending' && expiresAt.isAfter(DateTime.now());

  String get roleLabel => switch (role) {
        'client_owner' => 'Owner',
        'client_contact' => 'Contact',
        'client_viewer' => 'Viewer',
        _ => role,
      };
}

class ClientPortalAuthService {
  final _db = Supabase.instance.client;

  /// Accepts either a bare token or a full pasted invite URL -- a client
  /// copy-pasting straight from the email is the realistic case, not
  /// hand-typing a raw token. Two URL shapes reach real people: the email
  /// link (`.../accept-client-portal/TOKEN`) and the logged-out redirect a
  /// browser lands on (`.../client-portal-activate/TOKEN`) -- both must
  /// parse, since either one can end up pasted here.
  static String extractToken(String input) {
    final trimmed = input.trim();
    for (final marker in const ['accept-client-portal/', 'client-portal-activate/']) {
      final idx = trimmed.indexOf(marker);
      if (idx != -1) {
        return trimmed.substring(idx + marker.length).split(RegExp(r'[?#]')).first;
      }
    }
    if (trimmed.contains('://')) {
      final path = trimmed.split(RegExp(r'[?#]')).first;
      return path.split('/').where((s) => s.isNotEmpty).last;
    }
    return trimmed;
  }

  Future<InvitationPreview> preview(String token) async {
    final data = await _db.rpc('get_client_portal_invitation_preview', params: {
      'p_token': token,
    });
    return InvitationPreview.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// New client: create the account, scoped so it never bootstraps its own
  /// org (is_client_portal_invite mirrors what auth.store.ts's signUp()
  /// sends on web -- without it, handle_new_user() would give this profile
  /// its own "X's workspace" firm org, which is exactly the bug the user
  /// hit: an invited client's account came out as a firm instead of a
  /// portal client under the firm that invited them).
  Future<void> signUpAndAccept({
    required String email,
    required String password,
    required String displayName,
    required String token,
  }) async {
    final res = await _db.auth.signUp(
      email: email,
      password: password,
      data: {
        'name': displayName,
        'account_type': 'pyme_client',
        'intended_plan': 'starter',
        'is_client_portal_invite': true,
      },
    );
    if (res.session == null) {
      throw StateError(
        'Check your email to confirm your account, then sign in and accept the invitation again.',
      );
    }
    await acceptInvitation(token);
  }

  /// Existing account: sign in, then accept.
  Future<void> signInAndAccept({
    required String email,
    required String password,
    required String token,
  }) async {
    await _db.auth.signInWithPassword(email: email, password: password);
    await acceptInvitation(token);
  }

  Future<void> acceptInvitation(String token) async {
    await _db.rpc('accept_client_portal_invitation', params: {'p_token': token});
  }
}
