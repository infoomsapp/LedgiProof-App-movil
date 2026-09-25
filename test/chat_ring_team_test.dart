// Team-channel messages are plain messages: they light the ring blue when
// nothing else is waiting, and never outrank a client's tag.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/workspace_chat_service.dart';
import 'package:ledgiproof/utils/chat_ring.dart';

WorkspaceConversation conv(int unread, String? tag) =>
    WorkspaceConversation.fromRow({
      'id': 'c',
      'org_id': 'o',
      'client_id': 'k',
      'my_unread_count': unread,
      'my_unread_tag': tag,
    });

void main() {
  test('only team messages waiting -> blue', () {
    expect(chatRing([], teamUnread: 3).tag, MessageTag.normal);
    expect(chatRing([conv(0, null)], teamUnread: 1).tag, MessageTag.normal);
  });

  test('a client tag outranks the team channel', () {
    expect(chatRing([conv(1, 'urgent')], teamUnread: 5).tag, MessageTag.urgent);
    expect(chatRing([conv(1, 'pending')], teamUnread: 5).tag, MessageTag.pending);
  });

  test('nothing anywhere -> grey', () {
    expect(chatRing([], teamUnread: 0).tag, isNull);
  });

  test('inbox response reads team_unread and defaults to 0', () {
    final r = WorkspaceInboxResponse.fromJson({'role': 'bookkeeper', 'team_unread': 4});
    expect(r.teamUnread, 4);
    expect(WorkspaceInboxResponse.fromJson({'role': 'client'}).teamUnread, 0);
  });
}
