import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/books_service.dart';
import '../services/notification_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/quick_actions.dart';
import '../widgets/workspace_switcher.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  final Workspace workspace;
  final WorkspaceScope scope;
  final Future<void> Function(Workspace) onSwitch;
  final Future<void> Function() onCreatePersonal;

  const HomeScreen({
    super.key,
    required this.workspace,
    required this.scope,
    required this.onSwitch,
    required this.onCreatePersonal,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _books = BooksService();
  final _notifications = NotificationService();
  late Future<List<SemaphoreTx>> _queue;
  int _unread = 0;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _queue = _books.getReviewQueue(widget.workspace.orgId);
    _refreshUnread();
    // The badge is the reason `notifications` had to join the realtime
    // publication: without it a new message only showed up here on a manual
    // refresh, which is the same thing that made the web's bell feel dead.
    _channel = _notifications.subscribe(
      orgId: widget.workspace.orgId,
      onInsert: (_) => _refreshUnread(),
    );
  }

  @override
  void dispose() {
    final c = _channel;
    if (c != null) _notifications.unsubscribe(c);
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final n = await _notifications.unreadCount(widget.workspace.orgId);
      if (mounted) setState(() => _unread = n);
    } catch (_) {
      // A badge that cannot be counted is not worth an error in the user's
      // face; it simply stays as it was.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: WorkspaceSwitcher(
          scope: widget.scope,
          onSwitch: widget.onSwitch,
          onCreatePersonal: widget.onCreatePersonal,
        ),
        actions: [
          _BellButton(
            unread: _unread,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    NotificationsScreen(workspace: widget.workspace),
              ));
              _refreshUnread();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() { _queue = _books.getReviewQueue(widget.workspace.orgId); });
          await _queue;
        },
        child: FutureBuilder<List<SemaphoreTx>>(
          future: _queue,
          builder: (context, snap) {
            final count = snap.data?.length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NEEDS YOUR EYES',
                          style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      Text(
                        count == null ? '—' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // The cards are the person's own: Edit picks up to five and
                // reorders them (see widgets/quick_actions.dart).
                QuickActionsSection(workspace: widget.workspace),
                const SizedBox(height: 20),
                if (snap.hasError)
                  Text('Could not load your review queue.', style: TextStyle(color: AppColors.red)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const _BellButton({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(Icons.notifications_none, color: AppColors.inkMuted),
          tooltip: 'Notifications',
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
