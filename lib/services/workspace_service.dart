import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's active organization -- the mobile shell's stand-in
/// for the web app's fuller useUserRole() matrix. Just enough to decide what
/// the "Work" tab shows: an org's own invoices (solo/PYME) vs its client
/// list (a bookkeeping/accountant firm), via organizations.is_firm.
class Workspace {
  final String orgId;
  final String orgName;
  final String role; // owner / admin / accountant / auditor / approver / readonly
  final bool isFirm;

  Workspace({
    required this.orgId,
    required this.orgName,
    required this.role,
    required this.isFirm,
  });
}

class WorkspaceService {
  final _db = Supabase.instance.client;

  Future<Workspace?> loadActiveWorkspace() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;

    final membership = await _db
        .from('organization_memberships')
        .select('org_id, role, is_active')
        .eq('user_id', userId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

    if (membership == null) return null;

    final org = await _db
        .from('organizations')
        .select('id, name, is_firm')
        .eq('id', membership['org_id'] as String)
        .single();

    return Workspace(
      orgId: org['id'] as String,
      orgName: (org['name'] as String?) ?? 'Workspace',
      role: (membership['role'] as String?) ?? 'readonly',
      isFirm: (org['is_firm'] as bool?) ?? false,
    );
  }
}
