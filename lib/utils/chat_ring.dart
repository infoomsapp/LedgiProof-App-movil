import '../services/workspace_chat_service.dart';

/// What the floating chat bubble's ring should say. The ring follows the TAG
/// of what is waiting, the same semaphore colours the message bubbles use: a
/// plain message is blue, "Outstanding" amber, "Invoice" green, "Needs a
/// reply" red, and the most important tag across unread conversations wins.
/// (It used to count clients, which painted every ordinary unread message
/// amber.) Mirrors the web's lib/chat-ring.ts.
class ChatRing {
  /// Null when nothing is unread (grey ring).
  final MessageTag? tag;
  final String label;
  const ChatRing(this.tag, this.label);
}

const _priority = [
  MessageTag.urgent,
  MessageTag.pending,
  MessageTag.invoice,
  MessageTag.normal,
];

String _tagLabel(MessageTag t) => switch (t) {
      MessageTag.urgent => 'Needs a reply',
      MessageTag.pending => 'Outstanding',
      MessageTag.invoice => 'Invoice',
      MessageTag.normal => 'New message',
    };

/// [teamUnread] is the firm's team channel: a plain message, so it counts as
/// one unread "normal" entry (blue) and never outranks a client's tag.
ChatRing chatRing(
  Iterable<WorkspaceConversation> conversations, {
  int teamUnread = 0,
}) {
  final waiting = conversations.where((c) => c.myUnreadCount > 0).toList();
  if (waiting.isEmpty && teamUnread <= 0) {
    return const ChatRing(null, 'No unread messages');
  }
  // A conversation can be flagged unread without an unread message ("Mark as
  // unread"), so a missing tag counts as a plain message.
  final tags = [
    ...waiting.map((c) => c.myUnreadTag ?? MessageTag.normal),
    if (teamUnread > 0) MessageTag.normal,
  ];
  final top = _priority.firstWhere(tags.contains, orElse: () => MessageTag.normal);
  final n = tags.where((t) => t == top).length;
  return ChatRing(top, '${_tagLabel(top)} · $n conversation${n > 1 ? 's' : ''}');
}
