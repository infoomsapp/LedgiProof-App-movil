import 'package:flutter/material.dart';
import '../services/workspace_chat_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../widgets/lp_chat_brand_icon.dart';
import '../widgets/team_button.dart';
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

  // Last inbox that loaded successfully. A reload (pull to refresh, coming
  // back from a thread) keeps showing it instead of swapping the whole list
  // for a spinner, and a failed reload leaves it on screen.
  WorkspaceInboxResponse? _last;

  // Conversations the user just swiped away. Hidden immediately (a Dismissible
  // must leave the tree in the same frame it is dismissed) and forgotten once
  // the next inbox load confirms they are gone.
  final Set<String> _deleted = {};

  @override
  void initState() {
    super.initState();
    _inbox = _fetch();
  }

  Future<WorkspaceInboxResponse> _fetch() async {
    final res = await _service.getInbox(widget.workspace.orgId);
    _last = res;
    _deleted.removeWhere((id) => !res.conversations.any((c) => c.id == id));
    return res;
  }

  void _reload() {
    // A block body, not `=> _inbox = ...` -- an arrow body's value is the
    // assignment's value, which here is the Future getInbox() returns, and
    // setState() asserts at runtime that its callback returns void. A block
    // body with no explicit `return` is void regardless of what the last
    // statement evaluates to.
    setState(() {
      _inbox = _fetch();
    });
  }

  void _onConversationDeleted(String id) {
    setState(() => _deleted.add(id));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkspaceInboxResponse>(
      future: _inbox,
      builder: (context, snap) {
        // A portal client's relationship with their firm is never really "no
        // conversation" -- it's one accountant, always reachable, even right
        // after the firm deletes the thread from their own inbox (soft-
        // delete: workspace_conversations.deleted_at, which
        // get_workspace_inbox filters out for everyone, staff and client
        // alike). Real bug found live: that made the accountant's contact
        // vanish from the client's app with no way back in, since this
        // screen was the only chat entry point and it dead-ended on a static
        // "no conversations" message once the inbox came back empty. The web
        // side never had this problem -- its floating bubble hands
        // WorkspaceChatPanel the client's own clientId directly
        // (GlobalChatBubble.tsx) and skips the inbox list entirely for a
        // portal viewer, so a composer is always reachable regardless of
        // what the inbox query returns. Mirrored here: a portal client whose
        // inbox has loaded (successfully or not -- either way there is
        // nothing useful to list) goes straight to the thread with their
        // accountant instead of through this screen's own Scaffold/AppBar.
        // conversationId is deliberately null when the inbox has no row for
        // it -- ChatThreadScreen already handles that (the same path a firm
        // member gets opening a brand-new client): the first message sent
        // calls send_workspace_message, which is get-or-create and
        // resurrects the deleted row (with its full prior history) rather
        // than losing it.
        if (widget.workspace.isPortalClient &&
            snap.connectionState == ConnectionState.done &&
            !snap.hasError) {
          final conversations = snap.data?.conversations ?? [];
          return ChatThreadScreen(
            workspace: widget.workspace,
            conversationId: conversations.isEmpty
                ? null
                : conversations.first.id,
            clientId: widget.workspace.portalClientId!,
            clientName: widget.workspace.firmName ?? widget.workspace.orgName,
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Chat',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            // Team sits right next to the inbox title; firm members only.
            actions: [
              if (workspaceHasTeamChat(widget.workspace))
                TeamButton(workspace: widget.workspace),
            ],
          ),
          body: _buildInboxBody(context, snap),
        );
      },
    );
  }

  Widget _buildInboxBody(
    BuildContext context,
    AsyncSnapshot<WorkspaceInboxResponse> snap,
  ) {
    final data = snap.data ?? _last;
    // Spinner / error only while there is nothing to show yet.
    if (data == null && snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data == null && snap.hasError) {
      return _Empty(
        icon: Icons.error_outline,
        title: 'Could not load chat.',
        body: 'Check your connection and pull to retry.',
        onRetry: _reload,
      );
    }
    final conversations = (data?.conversations ?? [])
        .where((c) => !_deleted.contains(c.id))
        .toList();
    if (conversations.isEmpty) {
      return _Empty(
        icon: Icons.chat_bubble_outline,
        leadingWidget: const LpChatBrandIcon(size: 34),
        title: 'No conversations yet.',
        body: 'Message a client and it will show up here.',
        onRetry: _reload,
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: conversations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _ConversationRow(
          workspace: widget.workspace,
          conversation: conversations[i],
          // Clears only the firm's OWN side; the client keeps their copy.
          // The server limits it to owner/admin and the swipe springs back
          // with the reason otherwise. (A portal client never sees this list:
          // they go straight to their thread, which has its own delete.)
          canDelete: true,
          onOpened: _reload,
          onDeleted: () => _onConversationDeleted(conversations[i].id),
        ),
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
        title: const Text('Delete this conversation on your side?'),
        content: const Text(
          'The other side keeps their own copy, and it comes back if a new '
          'message arrives. This will not delete the client.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
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
      // The delete happens here, before the row is allowed to leave: if the
      // server refuses (or the network drops) the row springs back and says
      // why, instead of vanishing while the conversation still exists.
      confirmDismiss: (_) async {
        if (!await _confirmDelete(context)) return false;
        try {
          await WorkspaceChatService().deleteConversation(conversation.id);
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not delete: ${friendlyError(e)}')),
            );
          }
          return false;
        }
      },
      onDismissed: (_) => onDeleted(),
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
        await Navigator.of(context).push(
          MaterialPageRoute(
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
          ),
        );
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
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
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
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    required this.onRetry,
    this.leadingWidget,
  });

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
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}
