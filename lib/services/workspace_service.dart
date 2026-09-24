import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How an organization is classified. Ported from the web app's
/// src/lib/org-helpers.ts so both products agree on what a workspace IS:
/// the explicit boolean flags win, and account_type is only a fallback for
/// rows that pre-date those columns.
enum OrgCategory { personal, firm, clientCompany, unknown }

extension OrgCategoryLabel on OrgCategory {
  String get label {
    switch (this) {
      case OrgCategory.personal:
        return 'Personal';
      case OrgCategory.firm:
        return 'Firm';
      case OrgCategory.clientCompany:
        return 'Client';
      case OrgCategory.unknown:
        return 'Workspace';
    }
  }
}

/// The signed-in user's organization -- the mobile shell's stand-in for the
/// web app's fuller useUserRole() matrix. Just enough to decide what the
/// "Work" tab shows: an org's own invoices (solo/PYME) vs its client list
/// (a bookkeeping/accountant firm), via organizations.is_firm.
class Workspace {
  final String orgId;
  final String orgName;
  final String role; // owner / admin / accountant / auditor / approver / readonly
  final bool isFirm;
  final OrgCategory category;

  Workspace({
    required this.orgId,
    required this.orgName,
    required this.role,
    required this.isFirm,
    this.category = OrgCategory.unknown,
  });
}

/// Everything the shell needs to offer the Firm / Personal switch.
///
/// The rule for showing the switch is copied from the web's OrgSelector rather
/// than reinvented: the user's system_role must be bookkeeper, admin or
/// super_admin, AND they must own at least one firm workspace. A pyme_client
/// or an auditor never sees it, and neither does a plain solo user.
class WorkspaceScope {
  final List<Workspace> orgs;
  final Workspace active;
  final bool isToggleEligibleRole;

  WorkspaceScope({
    required this.orgs,
    required this.active,
    required this.isToggleEligibleRole,
  });

  List<Workspace> get personalOrgs =>
      orgs.where((o) => o.category == OrgCategory.personal).toList();
  List<Workspace> get firmOrgs =>
      orgs.where((o) => o.category == OrgCategory.firm).toList();
  List<Workspace> get clientOrgs =>
      orgs.where((o) => o.category == OrgCategory.clientCompany).toList();

  bool get hasPersonal => personalOrgs.isNotEmpty;

  /// Same condition as the web: eligible role AND at least one firm org.
  /// When there is no personal workspace yet the switch still shows, with the
  /// Personal side acting as a create action.
  bool get canToggle => isToggleEligibleRole && firmOrgs.isNotEmpty;
}

class WorkspaceService {
  final _db = Supabase.instance.client;

  /// Remembers the workspace the user was last in, so the app reopens where
  /// they left off instead of picking one arbitrarily.
  static const _lastOrgKey = 'ledgiproof_last_org_id';

  /// Roles for which the Personal/Firm switch is meaningful.
  static const _toggleEligibleRoles = {'bookkeeper', 'admin', 'super_admin'};

  static OrgCategory classify(Map<String, dynamic> org, String? accountType) {
    if (org['is_personal'] == true) return OrgCategory.personal;
    if (org['is_firm'] == true) return OrgCategory.firm;
    if (org['is_client'] == true) return OrgCategory.clientCompany;

    // Fallback for rows written before the flags existed, same order the web
    // helper uses.
    switch (accountType) {
      case 'self_employed':
        return OrgCategory.personal;
      case 'bookkeeper':
        return OrgCategory.firm;
      case 'pyme_client':
        return OrgCategory.clientCompany;
    }
    return OrgCategory.unknown;
  }

  /// Loads every workspace the user belongs to, not just one.
  ///
  /// The previous version took `.limit(1)` with no ordering, so an accountant
  /// who owns a firm, a second firm and a personal workspace got whichever row
  /// the database happened to return first. That is the bug this replaces.
  Future<WorkspaceScope?> loadScope() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;

    final profile = await _db
        .from('profiles')
        .select('system_role, account_type')
        .eq('id', userId)
        .maybeSingle();

    final rows = await _db
        .from('organization_memberships')
        .select(
            'org_id, role, organizations(id, name, is_firm, is_personal, is_client)')
        .eq('user_id', userId)
        .eq('is_active', true);

    final accountType = profile?['account_type'] as String?;
    final orgs = <Workspace>[];

    for (final r in (rows as List)) {
      final org = r['organizations'];
      if (org == null) continue;
      final map = Map<String, dynamic>.from(org as Map);
      orgs.add(Workspace(
        orgId: map['id'] as String,
        orgName: (map['name'] as String?) ?? 'Workspace',
        role: (r['role'] as String?) ?? 'readonly',
        isFirm: (map['is_firm'] as bool?) ?? false,
        category: classify(map, accountType),
      ));
    }

    if (orgs.isEmpty) return null;

    // Stable order so the picker never reshuffles: firm, personal, client.
    orgs.sort((a, b) {
      int rank(OrgCategory c) => switch (c) {
            OrgCategory.firm => 0,
            OrgCategory.personal => 1,
            OrgCategory.clientCompany => 2,
            OrgCategory.unknown => 3,
          };
      final byCat = rank(a.category).compareTo(rank(b.category));
      return byCat != 0 ? byCat : a.orgName.compareTo(b.orgName);
    });

    final remembered = await _readLastOrgId();
    final active = orgs.firstWhere(
      (o) => o.orgId == remembered,
      orElse: () => orgs.first,
    );

    final systemRole = profile?['system_role'] as String?;

    return WorkspaceScope(
      orgs: orgs,
      active: active,
      isToggleEligibleRole:
          systemRole != null && _toggleEligibleRoles.contains(systemRole),
    );
  }

  Future<void> rememberOrg(String orgId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastOrgKey, orgId);
    } catch (_) {
      // Remembering is a convenience; the switch still applies this session.
    }
  }

  Future<String?> _readLastOrgId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastOrgKey);
    } catch (_) {
      return null;
    }
  }

  /// Creates the accountant's own personal workspace through the same RPC the
  /// web uses, so a workspace created on the phone is identical to one created
  /// at the desk.
  Future<String> createPersonalOrg(String displayName) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('No session');
    final id = await _db.rpc('create_personal_org_for_bookkeeper', params: {
      'p_user_id': userId,
      'p_display_name': displayName,
    });
    return id as String;
  }

  /// Kept for callers that only need the single active workspace. Now backed
  /// by [loadScope], so it honours the remembered choice instead of returning
  /// an arbitrary row.
  Future<Workspace?> loadActiveWorkspace() async {
    final scope = await loadScope();
    return scope?.active;
  }
}
