import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only view of the org's linked bank accounts.
///
/// Linking a new account is NOT offered here on purpose: Plaid Link is a web
/// SDK and the exchange runs in the plaid-exchange edge function, so the phone
/// would only be able to start a flow it cannot finish. The app shows what is
/// connected and how fresh it is, and points at the web app to change it.
class BankConnection {
  final String id;
  final String? institutionName;
  final String? accountName;
  final String? mask;
  final String? accountType;
  final bool isActive;
  final String? syncStatus;
  final String? syncError;
  final DateTime? lastSyncedAt;

  /// Which client this account belongs to, when the workspace is a firm.
  /// Null in a personal or client workspace, where the books are the viewer's.
  final String? clientName;

  BankConnection({
    required this.id,
    required this.institutionName,
    required this.accountName,
    required this.mask,
    required this.accountType,
    required this.isActive,
    required this.syncStatus,
    required this.syncError,
    required this.lastSyncedAt,
    this.clientName,
  });

  String get label {
    final inst = institutionName ?? 'Bank';
    final acct = accountName == null ? '' : ' · $accountName';
    final tail = mask == null ? '' : ' ••$mask';
    return '$inst$acct$tail';
  }
}

class BankConnectionService {
  final _db = Supabase.instance.client;

  /// Explicit columns, never `*`. plaid_access_token and plaid_cursor are
  /// revoked from the `authenticated` role (migration
  /// restrict_plaid_token_columns_properly), so `*` would fail outright here,
  /// and the phone has no business holding them either way.
  Future<List<BankConnection>> load(String orgId) async {
    final rows = await _db
        .from('bank_connections')
        .select('id, institution_name, account_name, mask, account_type, '
            'is_active, sync_status, sync_error, last_synced_at, '
            'clients(display_name, company_name)')
        .eq('org_id', orgId)
        .order('connected_at', ascending: false);

    return (rows as List)
        .map((r) => BankConnection(
              id: r['id'] as String,
              institutionName: r['institution_name'] as String?,
              accountName: r['account_name'] as String?,
              mask: r['mask'] as String?,
              accountType: r['account_type'] as String?,
              isActive: (r['is_active'] as bool?) ?? false,
              syncStatus: r['sync_status'] as String?,
              syncError: r['sync_error'] as String?,
              lastSyncedAt: r['last_synced_at'] == null
                  ? null
                  : DateTime.tryParse(r['last_synced_at'] as String),
              clientName: r['clients'] == null
                  ? null
                  : ((r['clients'] as Map)['company_name'] as String?) ??
                      ((r['clients'] as Map)['display_name'] as String?),
            ))
        .toList();
  }
}
