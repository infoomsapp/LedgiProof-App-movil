import 'package:flutter/material.dart';
import '../services/bank_connection_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// The org's linked bank accounts, read only.
///
/// Connecting or disconnecting deliberately lives on the web: Plaid Link is a
/// web SDK and the token exchange runs in an edge function, so offering a
/// "Connect" button here would start a flow the phone cannot finish.
class ConnectionsScreen extends StatefulWidget {
  final Workspace workspace;
  const ConnectionsScreen({super.key, required this.workspace});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _service = BankConnectionService();
  late Future<List<BankConnection>> _conns;

  @override
  void initState() {
    super.initState();
    _conns = _service.load(widget.workspace.orgId);
  }

  void _reload() =>
      setState(() => _conns = _service.load(widget.workspace.orgId));

  @override
  Widget build(BuildContext context) {
    final isFirm = widget.workspace.category == OrgCategory.firm;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<BankConnection>>(
        future: _conns,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.error_outline,
              title: 'Could not load your connections.',
              body: 'Check your connection and try again.',
              onRetry: _reload,
            );
          }
          final conns = snap.data ?? [];
          if (conns.isEmpty) {
            return _Message(
              icon: Icons.account_balance_outlined,
              title: isFirm
                  ? 'No client accounts linked yet.'
                  : 'No bank accounts linked.',
              body: 'Bank accounts are linked from the web app at '
                  'ledgiproof.com; once linked they appear here.',
              onRetry: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // In firm mode these are the clients' accounts, not the
                // accountant's. Saying so up front is the whole point: the
                // firm's own books live in the personal workspace, and the two
                // must never be confused for one another.
                if (isFirm)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.blueBg,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.apartment_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Your clients’ accounts. Your own books are in '
                            'your personal workspace.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...conns.map((c) => _ConnCard(conn: c, showOwner: isFirm)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Linking or removing a bank account is done on the web app.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConnCard extends StatelessWidget {
  final BankConnection conn;
  final bool showOwner;
  const _ConnCard({required this.conn, this.showOwner = false});

  @override
  Widget build(BuildContext context) {
    final hasError = (conn.syncError ?? '').trim().isNotEmpty;
    final statusColor = !conn.isActive
        ? AppColors.inkSubtle
        : hasError
            ? AppColors.red
            : AppColors.green;
    final statusText = !conn.isActive
        ? 'Disconnected'
        : hasError
            ? 'Needs attention'
            : (conn.syncStatus ?? 'Connected');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  size: 18, color: AppColors.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showOwner && conn.clientName != null) ...[
                      Text(conn.clientName!,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      conn.label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(statusText,
                  style: TextStyle(fontSize: 12.5, color: statusColor)),
              const Spacer(),
              Text(
                conn.lastSyncedAt == null
                    ? 'Never synced'
                    : 'Synced ${_ago(conn.lastSyncedAt!)}',
                style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
              ),
            ],
          ),
          if (hasError) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.redBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'This account needs to be reconnected on the web app.',
                style: TextStyle(fontSize: 12, color: AppColors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onRetry;
  const _Message(
      {required this.icon,
      required this.title,
      required this.body,
      required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.inkSubtle),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}
