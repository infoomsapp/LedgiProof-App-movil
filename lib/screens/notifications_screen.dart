import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

/// What the web's notification bell shows, on the phone.
///
/// The list updates live: `notifications` joined the realtime publication on
/// 2026-09-24, which is also the day the web's own subscription started
/// firing for the first time.
class NotificationsScreen extends StatefulWidget {
  final Workspace workspace;
  const NotificationsScreen({super.key, required this.workspace});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  late Future<List<AppNotification>> _future;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _service.subscribe(
      orgId: widget.workspace.orgId,
      onInsert: (_) {
        // Reload rather than splice the row in: the list is short, and a
        // refetch cannot drift out of step with what the server actually has.
        if (mounted) _load();
      },
    );
  }

  @override
  void dispose() {
    final c = _channel;
    if (c != null) _service.unsubscribe(c);
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = _service.list(orgId: widget.workspace.orgId);
    });
  }

  Future<void> _markAll() async {
    try {
      await _service.markAllRead(widget.workspace.orgId);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, 'Could not update these.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _markAll,
            child: Text('Mark all read',
                style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
          ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (snap.hasError || items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        snap.hasError
                            ? Icons.error_outline
                            : Icons.notifications_none,
                        size: 30,
                        color: AppColors.inkSubtle),
                    const SizedBox(height: 12),
                    Text(
                        snap.hasError
                            ? 'Could not load your notifications.'
                            : 'Nothing new.',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    const SizedBox(height: 6),
                    Text(
                      snap.hasError
                          ? 'Check your connection and try again.'
                          : 'Messages, documents and alerts for this '
                              'workspace land here.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                        onPressed: _load, child: const Text('Reload')),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) => _Row(
                item: items[i],
                onTap: () async {
                  if (!items[i].isRead) {
                    await _service.markRead(items[i].id);
                    if (mounted) _load();
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onTap;
  const _Row({required this.item, required this.onTap});

  static IconData _iconFor(String type) => switch (type) {
        'new_message' => Icons.chat_bubble_outline,
        'sensitive_data_flagged' => Icons.shield_outlined,
        _ => Icons.notifications_none,
      };

  static Color _colourFor(String type) => switch (type) {
        'sensitive_data_flagged' => AppColors.red,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            // Unread is carried by a tinted panel and a dot, not by colour
            // alone -- a single hue doing all the work fails for anyone who
            // cannot separate it from the surface.
            color: item.isRead ? AppColors.surface : AppColors.blueBg,
            border: Border.all(
                color: item.isRead ? AppColors.border : AppColors.primary),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconFor(item.type),
                  size: 18, color: _colourFor(item.type)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: item.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: AppColors.ink)),
                    if ((item.body ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(item.body!,
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.inkMuted)),
                    ],
                    const SizedBox(height: 5),
                    Text(_ago(item.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: AppColors.inkSubtle)),
                  ],
                ),
              ),
              if (!item.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return t.toIso8601String().substring(0, 10);
  }
}
