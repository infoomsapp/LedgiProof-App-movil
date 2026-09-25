// The floating bubble's ring follows the TAG of what is unread, not how many
// clients are waiting: a plain message must be blue, never amber.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/workspace_chat_service.dart';
import 'package:ledgiproof/utils/chat_ring.dart';

WorkspaceConversation conv(int unread, [String? tag, bool withTag = true]) =>
    WorkspaceConversation.fromRow({
      'id': 'c$unread${tag ?? ''}',
      'org_id': 'o',
      'client_id': 'k',
      'my_unread_count': unread,
      if (withTag) 'my_unread_tag': tag,
    });

void main() {
  test('nothing unread -> no tag (grey)', () {
    expect(chatRing([]).tag, isNull);
    expect(chatRing([conv(0, 'urgent')]).tag, isNull);
  });

  test('a plain unread message is normal (blue), however many clients', () {
    expect(chatRing([conv(1, 'normal')]).tag, MessageTag.normal);
    expect(
      chatRing([conv(1, 'normal'), conv(2, 'normal'), conv(1, 'normal')]).tag,
      MessageTag.normal,
    );
  });

  test('the most important tag across conversations wins', () {
    expect(chatRing([conv(1, 'normal'), conv(1, 'pending')]).tag, MessageTag.pending);
    expect(
      chatRing([conv(1, 'pending'), conv(1, 'urgent'), conv(3, 'normal')]).tag,
      MessageTag.urgent,
    );
    expect(chatRing([conv(1, 'invoice'), conv(1, 'normal')]).tag, MessageTag.invoice);
  });

  test('a missing tag (old server / Mark as unread) counts as normal', () {
    expect(chatRing([conv(1, null, false)]).tag, MessageTag.normal);
    expect(chatRing([conv(1, null)]).tag, MessageTag.normal);
  });

  test('label names the winning tag and its conversation count', () {
    expect(
      chatRing([conv(1, 'urgent'), conv(1, 'urgent'), conv(1, 'normal')]).label,
      'Needs a reply · 2 conversations',
    );
    expect(chatRing([conv(4, 'normal')]).label, 'New message · 1 conversation');
  });
}
