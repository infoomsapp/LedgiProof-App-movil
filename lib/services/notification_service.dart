import 'package:supabase_flutter/supabase_flutter.dart';

/// The same `notifications` rows the web's NotificationBell reads, scoped the
/// same way.
///
/// The org scoping is not optional polish. The web fixed a real bug where a
/// user belonging to several organizations saw every org's notifications mixed
/// together, and where "mark all read" silently cleared notifications from an
/// org they were not even looking at. Both filters are copied here so the two
/// products cannot disagree about what belongs to the workspace you are in.
class AppNotification {
  final String id;
  final String orgId;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  AppNotification.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        orgId = r['org_id'] as String,
        type = (r['type'] as String?) ?? '',
        title = (r['title'] as String?) ?? '',
        body = r['body'] as String?,
        isRead = (r['is_read'] as bool?) ?? false,
        createdAt = DateTime.tryParse((r['created_at'] as String?) ?? '') ??
            DateTime.now();
}

class NotificationService {
  final _db = Supabase.instance.client;

  // A plain 'new_message' notification is deliberately excluded on mobile
  // (list, count, and the realtime subscribe() filter below) -- the
  // floating chat bubble is always on screen here and already carries its
  // own semaphore-colored unread badge for exactly that, so duplicating it
  // into the bell too was just noise: every message rang the bell AND lit
  // the bubble for the same event. 'sensitive_data_flagged' and anything
  // else still comes through -- those aren't already surfaced anywhere
  // else. The web keeps 'new_message' as-is; it has no equivalent
  // always-visible bubble outside the chat panel itself.
  static const _mutedType = 'new_message';

  Future<List<AppNotification>> list({
    required String orgId,
    int limit = 50,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _db
        .from('notifications')
        .select('id, org_id, type, title, body, is_read, created_at')
        .eq('user_id', userId)
        .eq('org_id', orgId)
        .neq('type', _mutedType)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => AppNotification.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<int> unreadCount(String orgId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return 0;
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('org_id', orgId)
        .eq('is_read', false)
        .neq('type', _mutedType);
    return (rows as List).length;
  }

  Future<void> markRead(String id) async {
    await _db.from('notifications').update({
      'is_read': true,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> markAllRead(String orgId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    await _db
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('org_id', orgId)
        .eq('is_read', false);
  }

  /// Live inserts for this user. Supabase can filter a subscription on one
  /// column only, so this listens on user_id and the caller drops anything
  /// belonging to another org -- the same shape, and the same reason, as the
  /// web hook.
  ///
  /// This only began working on 2026-09-24: `notifications` was missing from
  /// the supabase_realtime publication, so the web's equivalent subscription
  /// had never once fired and its bell only updated on a page load.
  RealtimeChannel subscribe({
    required String orgId,
    required void Function(AppNotification) onInsert,
  }) {
    final userId = _db.auth.currentUser?.id;
    final channel = _db.channel('notifications:${userId ?? 'anon'}:$orgId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final row = Map<String, dynamic>.from(payload.newRecord);
        if (row['org_id'] != orgId) return;
        if (row['type'] == _mutedType) return;
        onInsert(AppNotification.fromRow(row));
      },
    ).subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _db.removeChannel(channel);
  }
}
