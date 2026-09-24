import 'package:supabase_flutter/supabase_flutter.dart';
import 'workspace_chat_service.dart' show MessageSenderRole, MessageKind;

/// Mirrors src/services/chat-tx.service.ts -- the per-TRANSACTION chat,
/// separate from workspace_chat_service.dart's per-CLIENT inbox chat. Each
/// transaction has at most one conversation (open_or_get_transaction_conversation
/// creates it lazily), reused across every message about that transaction.
MessageSenderRole _senderRoleFrom(String? v) => switch (v) {
      'bookkeeper' => MessageSenderRole.bookkeeper,
      'client' => MessageSenderRole.client,
      _ => MessageSenderRole.system,
    };

MessageKind _messageKindFrom(String? v) => switch (v) {
      'in' => MessageKind.in_,
      'out' => MessageKind.out,
      'ai' => MessageKind.ai,
      _ => MessageKind.system,
    };

class TransactionMessage {
  final String id;
  final String? senderId;
  final MessageSenderRole senderRole;
  final String? body;
  final MessageKind messageKind;
  final DateTime createdAt;
  final String? senderName;

  TransactionMessage.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        senderId = r['sender_id'] as String?,
        senderRole = _senderRoleFrom(r['sender_role'] as String?),
        body = r['body'] as String?,
        messageKind = _messageKindFrom(r['message_kind'] as String?),
        createdAt = DateTime.tryParse((r['created_at'] as String?) ?? '') ??
            DateTime.now(),
        senderName = r['sender_name'] as String?;
}

class TransactionMessagesResponse {
  final String conversationId;
  final String status;
  final bool hasMore;
  final List<TransactionMessage> messages;

  TransactionMessagesResponse.fromJson(Map<String, dynamic> j)
      : conversationId = j['conversation_id'] as String,
        status = (j['status'] as String?) ?? 'open',
        hasMore = (j['has_more'] as bool?) ?? false,
        messages = ((j['messages'] as List?) ?? [])
            .map((r) => TransactionMessage.fromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
}

class TransactionChatService {
  final _db = Supabase.instance.client;

  Future<String> openOrGetConversation(String transactionId) async {
    final data = await _db.rpc('open_or_get_transaction_conversation', params: {
      'p_transaction_id': transactionId,
    });
    return data as String;
  }

  Future<TransactionMessagesResponse> getMessages(String conversationId,
      {int limit = 50}) async {
    final data = await _db.rpc('get_transaction_messages', params: {
      'p_conversation_id': conversationId,
      'p_limit': limit,
    });
    return TransactionMessagesResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    await _db.rpc('send_transaction_message', params: {
      'p_conversation_id': conversationId,
      'p_body': body,
      'p_channels': ['chat'],
    });
  }

  Future<void> markRead(String conversationId) async {
    await _db.rpc('mark_transaction_messages_read', params: {
      'p_conversation_id': conversationId,
    });
  }
}
