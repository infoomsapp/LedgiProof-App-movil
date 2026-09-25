import 'package:flutter/material.dart';
import '../services/workspace_chat_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lp_chat_brand_icon.dart';
import 'chat_thread_screen.dart';

/// The conversation list. For a firm workspace this is one row per client
/// (the same firm-wide inbox the web app's WorkspaceChatPanel shows). For a
/// portal-client workspace, get_workspace_inbox still returns the same
/// shape, scoped down to that client's own single conversation with the
/// firm -- the RLS/RPC layer does that narrowing, not this screen.
class ChatInboxScreen extends StatefulWidget {
  final Workspace workspace;
  const ChatInboxScreen({super.key, required this.workspace});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  final _service = WorkspaceChatService();
  late Future<WorkspaceInboxResponse> _inbox;

  @override
  void initState() {
    super.initState();
    _inbox = _service.getInbox(widget.workspace.orgId);
  }

  void _reload() {
    // A block body, not `=> _inbox = ...` -- an arrow body's value is the
    // assignment's value, which here is the Future getInbox() returns, and
    // setState() asserts at runtime that its callback returns void. A block
    // body with no explicit `return` is void regardless of what the last
    // statement evaluates to.
    setState(() { _inbox = _service.getInbox(widget.workspace.orgId); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<WorkspaceInboxResponse>(
        future: _inbox,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Empty(
              icon: Icons.error_outline,
              title: 'Could not load chat.',
              body: 'Check your connection and pull to retry.',
              onRetry: _reload,
            );
          }
          final conversations = snap.data?.conversations ?? [];
          if (conversations.isEmpty) {
            return _Empty(
              icon: Icons.chat_bubble_outline,
              leadingWidget: const LpChatBrandIcon(size: 34),
              title: 'No conversations yet.',
              body: widget.workspace.isPortalClient
                  ? 'Messages from your accountant will show up here.'
                  : 'Message a client and it will show up here.',
              onRetry: _reload,
            );
          }
          final isStaff = snap.data?.role == 'bookkeeper';
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ConversationRow(
                workspace: widget.workspace,
                conversation: conversations[i],
                // Delete is staff-only, matching the web's own menu (a
                // conversation is deleted from the FIRM's inbox declutter
                // need, never something a client does to their own copy).
                canDelete: isStaff,
                onOpened: _reload,
                onDeleted: _reload,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final Workspace workspace;
  final WorkspaceConversation conversation;
  final bool canDelete;
  final VoidCallback onOpened;
  final VoidCallback onDeleted;
  const _ConversationRow({
    required this.workspace,
    required this.conversation,
    required this.canDelete,
    required this.onOpened,
    required this.onDeleted,
  });

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this conversation?'),
        content: const Text(
            'This removes it from your inbox for good — it will not delete the client.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final row = _buildRow(context);
    if (!canDelete) return row;
    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        await WorkspaceChatService().deleteConversation(conversation.id);
        onDeleted();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: row,
    );
  }

  Widget _buildRow(BuildContext context) {
    final unread = conversation.myUnreadCount > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            workspace: workspace,
            conversationId: conversation.id,
            clientId: conversation.clientId,
            // A portal client talking to their firm sees the firm's name,
            // not their own business name back at themselves -- staff still
            // sees the actual client's name, same as before.
            clientName: workspace.isPortalClient
                ? (workspace.firmName ?? workspace.orgName)
                : conversation.clientName,
          ),
        ));
        onOpened();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workspace.isPortalClient
                        ? (workspace.firmName ?? workspace.orgName)
                        : conversation.clientName,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  if (conversation.lastMessagePreview != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      conversation.lastMessagePreview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: unread ? AppColors.ink : AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conversation.myUnreadCount}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final Widget? leadingWidget;
  final String title;
  final String body;
  final VoidCallback onRetry;
  const _Empty(
      {required this.icon,
      required this.title,
      required this.body,
      required this.onRetry,
      this.leadingWidget});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            leadingWidget ?? Icon(icon, size: 30, color: AppColors.inkSubtle),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
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
