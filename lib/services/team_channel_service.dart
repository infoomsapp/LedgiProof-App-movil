import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors src/services/team-channel.service.ts: ONE channel per firm
/// organization, visible only to the firm's own members (never clients).
/// Text only. Every member -- owner and admin included -- deletes only their
/// own messages.
class TeamMessage {
  final String id;
  final String? senderId;
  final String? senderName;

  /// Null once the sender deleted it.
  final String? body;
  final DateTime createdAt;
  final bool isDeleted;

  TeamMessage.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        senderId = r['sender_id'] as String?,
        senderName = r['sender_name'] as String?,
        body = r['body'] as String?,
        createdAt =
            DateTime.tryParse((r['created_at'] as String?) ?? '') ?? DateTime.now(),
        isDeleted = (r['is_deleted'] as bool?) ?? false;
}

class TeamChannelPage {
  final bool hasMore;

  /// created_at of the oldest message in this page, exactly as the server sent
  /// it -- passed back verbatim as `before` to fetch the page before it.
  final String? oldestAt;
  final int unreadCount;
  final List<TeamMessage> messages;

  TeamChannelPage.fromJson(Map<String, dynamic> j)
      : hasMore = (j['has_more'] as bool?) ?? false,
        oldestAt = j['oldest_at'] as String?,
        unreadCount = (j['unread_count'] as num?)?.toInt() ?? 0,
        messages = ((j['messages'] as List?) ?? [])
            .map((r) => TeamMessage.fromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
}

class TeamChannelService {
  final _db = Supabase.instance.client;

  Future<TeamChannelPage> getChannel(String orgId,
      {int limit = 50, String? before}) async {
    final params = <String, dynamic>{'p_org_id': orgId, 'p_limit': limit};
    if (before != null) params['p_before'] = before;
    final data = await _db.rpc('get_team_channel', params: params);
    return TeamChannelPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Cheap: one message is enough to learn the unread count.
  Future<int> unreadCount(String orgId) async =>
      (await getChannel(orgId, limit: 1)).unreadCount;

  Future<void> send(String orgId, String body) async {
    await _db.rpc('send_team_message', params: {'p_org_id': orgId, 'p_body': body});
  }

  Future<void> markRead(String orgId) async {
    await _db.rpc('mark_team_channel_read', params: {'p_org_id': orgId});
  }

  Future<void> deleteMine(String messageId) async {
    await _db.rpc('delete_team_message', params: {'p_message_id': messageId});
  }
}
