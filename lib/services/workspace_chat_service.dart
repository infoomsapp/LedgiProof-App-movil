import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors src/services/workspace-chat.service.ts's RPC contract exactly --
/// same 7 RPCs, same param names, same shapes. This is workspace-level chat
/// (bookkeeper <-> client), separate from any per-transaction chat.
/// What a message is ABOUT, which is why it is a tag and not a priority.
/// Three of the four state a fact; only [urgent] is a self-assessment, and it
/// is the only one that can inflate. Mirrors the workspace_messages.message_tag
/// CHECK constraint exactly.
enum MessageTag { normal, pending, invoice, urgent }

MessageTag _messageTagFrom(String? v) => switch (v) {
      'pending' => MessageTag.pending,
      'invoice' => MessageTag.invoice,
      'urgent' => MessageTag.urgent,
      _ => MessageTag.normal,
    };

String messageTagTo(MessageTag t) => switch (t) {
      MessageTag.pending => 'pending',
      MessageTag.invoice => 'invoice',
      MessageTag.urgent => 'urgent',
      MessageTag.normal => 'normal',
    };

enum MessageSenderRole { bookkeeper, client, system }
enum MessageKind { in_, out, system, ai }

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

String _messageKindTo(MessageKind k) => switch (k) {
      MessageKind.in_ => 'in',
      MessageKind.out => 'out',
      MessageKind.ai => 'ai',
      MessageKind.system => 'system',
    };

class WorkspaceConversation {
  final String id;
  final String orgId;
  final String clientId;
  final String clientName;
  final String? clientEmail;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final MessageSenderRole? lastMessageSenderRole;
  final bool isArchived;
  final int myUnreadCount;

  WorkspaceConversation.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        orgId = r['org_id'] as String,
        clientId = r['client_id'] as String,
        clientName = (r['client_name'] as String?) ?? 'Client',
        clientEmail = r['client_email'] as String?,
        lastMessageAt = r['last_message_at'] == null
            ? null
            : DateTime.tryParse(r['last_message_at'] as String),
        lastMessagePreview = r['last_message_preview'] as String?,
        lastMessageSenderRole = r['last_message_sender_role'] == null
            ? null
            : _senderRoleFrom(r['last_message_sender_role'] as String?),
        isArchived = (r['is_archived'] as bool?) ?? false,
        myUnreadCount = (r['my_unread_count'] as num?)?.toInt() ?? 0;
}

class WorkspaceInboxResponse {
  final String role; // 'bookkeeper' | 'client'
  final int total;
  final int unreadTotal;
  final List<WorkspaceConversation> conversations;

  WorkspaceInboxResponse.fromJson(Map<String, dynamic> j)
      : role = (j['role'] as String?) ?? 'client',
        total = (j['total'] as num?)?.toInt() ?? 0,
        unreadTotal = (j['unread_total'] as num?)?.toInt() ?? 0,
        conversations = ((j['conversations'] as List?) ?? [])
            .map((r) => WorkspaceConversation.fromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
}

class WorkspaceMessage {
  final String id;
  final String conversationId;
  final String? senderId;
  final MessageSenderRole senderRole;
  final String? body;
  final MessageKind messageKind;
  final bool aiGenerated;
  final DateTime createdAt;
  final String? senderName;

  final MessageTag tag;

  /// Set when the message carries a file. The row itself only holds the id;
  /// the signed URL is fetched on demand through DocumentService, so a thread
  /// never mints URLs for files nobody opens.
  final String? documentId;

  WorkspaceMessage.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        conversationId = r['conversation_id'] as String,
        senderId = r['sender_id'] as String?,
        senderRole = _senderRoleFrom(r['sender_role'] as String?),
        body = r['body'] as String?,
        messageKind = _messageKindFrom(r['message_kind'] as String?),
        aiGenerated = (r['ai_generated'] as bool?) ?? false,
        createdAt = DateTime.tryParse((r['created_at'] as String?) ?? '') ??
            DateTime.now(),
        senderName = r['sender_name'] as String?,
        documentId = r['document_id'] as String?,
        tag = _messageTagFrom(r['message_tag'] as String?);
}

class WorkspaceMessagesResponse {
  final bool hasMore;
  final List<WorkspaceMessage> messages;

  WorkspaceMessagesResponse.fromJson(Map<String, dynamic> j)
      : hasMore = (j['has_more'] as bool?) ?? false,
        messages = ((j['messages'] as List?) ?? [])
            .map((r) => WorkspaceMessage.fromRow(Map<String, dynamic>.from(r as Map)))
            .toList();
}

class WorkspaceChatService {
  final _db = Supabase.instance.client;

  Future<WorkspaceInboxResponse> getInbox(String orgId,
      {bool archived = false, int limit = 50}) async {
    final data = await _db.rpc('get_workspace_inbox', params: {
      'p_org_id': orgId,
      'p_archived': archived,
      'p_limit': limit,
    });
    return WorkspaceInboxResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<WorkspaceMessagesResponse> getMessages(String conversationId,
      {int limit = 50, String? before}) async {
    final params = <String, dynamic>{
      'p_conversation_id': conversationId,
      'p_limit': limit,
    };
    if (before != null) params['p_before'] = before;
    final data = await _db.rpc('get_workspace_messages', params: params);
    return WorkspaceMessagesResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// p_context_ref is always passed (as null here) -- the DB has two RPC
  /// overloads that differ only in that param's presence, and PostgreSQL
  /// can't pick one when it's omitted. Same fix the web's service applies.
  /// [body] may be empty when [documentId] is set: the RPC accepts a message
  /// that is only an attachment, and rejects one that is neither.
  Future<Map<String, dynamic>> sendMessage({
    required String orgId,
    required String clientId,
    String body = '',
    String? documentId,
    MessageTag tag = MessageTag.normal,
    MessageKind messageKind = MessageKind.in_,
    bool clientVisible = true,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty && documentId == null) {
      throw ArgumentError('A message needs a body or an attachment');
    }
    final data = await _db.rpc('send_workspace_message', params: {
      'p_org_id': orgId,
      'p_client_id': clientId,
      if (trimmed.isNotEmpty) 'p_body': trimmed,
      'p_document_id': ?documentId,
      'p_message_kind': _messageKindTo(messageKind),
      'p_message_tag': messageTagTo(tag),
      'p_client_visible': clientVisible,
      'p_context_ref': null,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> markRead(String conversationId) async {
    await _db.rpc('mark_workspace_messages_read', params: {
      'p_conversation_id': conversationId,
    });
  }

  Future<void> archive(String conversationId) async {
    await _db.rpc('archive_workspace_conversation', params: {
      'p_conversation_id': conversationId,
    });
  }

  Future<void> restore(String conversationId) async {
    await _db.rpc('restore_workspace_conversation', params: {
      'p_conversation_id': conversationId,
    });
  }
}
