import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/document_service.dart';
import '../services/workspace_chat_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../widgets/audited_status_check.dart';
import '../widgets/message_tag_style.dart';

/// One conversation's messages, plus a text field to reply. Works for both
/// a firm member (sender_role bookkeeper) and a portal client (sender_role
/// client) -- which one the server records is decided by the RPC from the
/// caller's own membership, never sent by this screen.
class ChatThreadScreen extends StatefulWidget {
  final Workspace workspace;

  /// Null when the thread does not exist yet -- opening a client from the
  /// Work tab is allowed before anyone has written anything. The first send
  /// creates the conversation server-side (send_workspace_message is
  /// get-or-create) and hands back its id, so history can start loading from
  /// that point on.
  final String? conversationId;
  final String clientId;
  final String clientName;

  const ChatThreadScreen({
    super.key,
    required this.workspace,
    this.conversationId,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with WidgetsBindingObserver {
  final _service = WorkspaceChatService();
  final _docs = DocumentService();
  MessageTag _tag = MessageTag.normal;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late Future<WorkspaceMessagesResponse> _future;
  bool _sending = false;

  String? get _myUserId => Supabase.instance.client.auth.currentUser?.id;

  String? _conversationId;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversationId = widget.conversationId;
    // Genuine open -- the only place this screen marks anything read on its
    // own initiative. Everything after this must earn a mark-read the same
    // way: an explicit sign the person is actually looking, not just a
    // passive DB push.
    _future = _load(markAsRead: true);
    _subscribeRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Real bug found live: a message sent from the web (staff) showed as read
  // on the sender's side the instant it arrived, even though nobody had
  // opened it on the recipient's phone. Cause: the realtime callback below
  // called _reload(), which called the OLD _load() that unconditionally
  // marked-read on every call -- so a screen merely left mounted in the
  // background (app backgrounded, thread not actually being looked at)
  // silently marked every incoming message read the moment Realtime pushed
  // it. Mark-read must follow genuine presence: opening the screen (above)
  // or the app coming back to THIS screen in the foreground (below) --
  // never a passive background refresh.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _markReadNow();
    }
  }

  void _markReadNow() {
    final id = _conversationId;
    if (id == null) return;
    unawaited(_service.markRead(id).catchError((_) {}));
  }

  // UPDATE specifically catches the read-receipt flip -- without it, the
  // check only ever appeared on this viewer's next reload (a new message,
  // reopening the thread), never live the instant the other side actually
  // read it, which defeats the point of a live receipt. Scoped to this
  // conversation only (not every workspace_messages row) since a thread
  // screen only cares about its own. Deliberately does NOT mark anything
  // read -- see the note on didChangeAppLifecycleState above.
  void _subscribeRealtime() {
    if (_channel != null) return; // already subscribed
    final convId = _conversationId;
    if (convId == null) return;
    _channel = Supabase.instance.client
        .channel('workspace-chat-thread-$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (_) { if (mounted) _reload(); },
        )
        .subscribe();
  }

  Future<WorkspaceMessagesResponse> _load({bool markAsRead = false}) async {
    final id = _conversationId;
    // Nothing written yet: show an empty thread rather than asking the RPC
    // for a conversation that does not exist (it raises 'conversation not
    // found', which would read as an error to the user for a perfectly
    // ordinary "first message to this client").
    if (id == null) {
      return WorkspaceMessagesResponse.fromJson(const {'messages': []});
    }
    final res = await _service.getMessages(id);
    if (markAsRead) {
      unawaited(_service.markRead(id).catchError((_) {}));
    }
    return res;
  }

  // A block body, not `=> _future = _load()` -- see the matching note in
  // chat_inbox_screen.dart's _reload(); same runtime "setState() callback
  // returned a Future" assertion, same fix. markAsRead defaults false: a
  // realtime-triggered reload must never silently mark-read (see above) --
  // only a genuine user action (sending a message opens the thread just as
  // surely as tapping into it) passes true explicitly.
  void _reload({bool markAsRead = false}) =>
      setState(() { _future = _load(markAsRead: markAsRead); });

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text('This cannot be undone.'),
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
    if (confirmed != true) return;
    try {
      await _service.deleteMessage(messageId);
      _reload(markAsRead: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${friendlyError(e)}')),
      );
    }
  }

  /// Attach a photo: take one or pick from the gallery, upload it, then send
  /// it as a message. Photos only for now -- image_picker cannot browse
  /// arbitrary files, so picking a PDF stored on the phone would need a
  /// second dependency. The web side keeps accepting PDFs either way, and a
  /// PDF that arrives from there opens fine here.
  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              title: Text('Take a photo', style: TextStyle(color: AppColors.ink)),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: Text('Choose from gallery', style: TextStyle(color: AppColors.ink)),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final documentId = await _docs.uploadAttachment(
        orgId: widget.workspace.orgId,
        clientId: widget.clientId,
        file: File(picked.path),
      );
      final res = await _service.sendMessage(
        orgId: widget.workspace.orgId,
        clientId: widget.clientId,
        body: _controller.text,
        documentId: documentId,
        tag: _tag,
      );
      _warnIfUrgentInflation(res);
      _tag = MessageTag.normal;
      _conversationId ??= res['conversation_id'] as String?;
      _subscribeRealtime();
      _controller.clear();
      _reload(markAsRead: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The server counts how many times this sender has played the urgent card
  /// in this conversation in the last 7 days. Past the third, say so once --
  /// a nudge, not a block. Refusing to send somebody's genuinely urgent fourth
  /// message would cost more than the inflation it prevents, which is why the
  /// database returns the count instead of enforcing a cap.
  void _warnIfUrgentInflation(Map<String, dynamic> res) {
    final count = (res['recent_urgent_count'] as num?)?.toInt() ?? 0;
    if (count < 4 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count urgent messages to this client this week. Urgent stops '
          'meaning urgent if everything is.',
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await _service.sendMessage(
        orgId: widget.workspace.orgId,
        clientId: widget.clientId,
        body: text,
        tag: _tag,
      );
      _warnIfUrgentInflation(res);
      _tag = MessageTag.normal;   // one message, one tag: never sticky
      // First message in a brand-new thread: keep the id the server just
      // created so history loads from here on.
      _conversationId ??= res['conversation_id'] as String?;
      _subscribeRealtime();
      _controller.clear();
      _reload(markAsRead: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<WorkspaceMessagesResponse>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Could not load messages.',
                        style: TextStyle(color: AppColors.inkMuted)),
                  );
                }
                final messages = snap.data?.messages ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No messages yet. Say hello.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    // Server returns oldest-first; render newest-first without
                    // re-sorting by just walking the list backwards.
                    final m = messages[messages.length - 1 - i];
                    final isMine = m.senderId != null && m.senderId == _myUserId;
                    // Staff can moderate any message in their org's
                    // conversations (matches the server-side RPC check
                    // exactly); a portal client can only delete their own.
                    final canModerate = !widget.workspace.isPortalClient;
                    // Same viewer/other split as the web's readReceiptIcon():
                    // staff sees whether the client has read it, and vice
                    // versa.
                    final readByOther = canModerate ? m.readByClient : m.readByBookkeeper;
                    return _MessageBubble(
                      message: m,
                      isMine: isMine,
                      canDelete: !m.isDeleted && (isMine || canModerate),
                      onDelete: () => _deleteMessage(m.id),
                      readByOther: readByOther,
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
              onAttach: _attach,
              tag: _tag,
              onTagChanged: (t) => setState(() => _tag = t)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final WorkspaceMessage message;
  final bool isMine;
  final bool canDelete;
  final VoidCallback onDelete;
  final bool readByOther;
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.canDelete,
    required this.onDelete,
    required this.readByOther,
  });

  @override
  Widget build(BuildContext context) {
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final tagged = message.tag != MessageTag.normal;
    final tc = tagColours(message.tag);

    // A tagged message is painted in its tag's colours on BOTH sides of the
    // thread: the point is that the reason stands out, not who sent it. An
    // untagged one keeps the ordinary mine/theirs contrast.
    final bg = tagged
        ? tc.bg
        : (isMine ? AppColors.primary : AppColors.surface);
    final fg = tagged ? AppColors.ink : (isMine ? Colors.white : AppColors.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMine && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4),
              child: Text(message.senderName!,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSubtle)),
            ),
          GestureDetector(
            onLongPress: canDelete ? onDelete : null,
            child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(
                  color: tagged
                      ? tc.ink
                      : (isMine ? Colors.transparent : AppColors.border),
                  width: tagged ? 1.2 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: message.isDeleted
                ? Text(
                    'This message was deleted',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: isMine ? Colors.white70 : AppColors.inkMuted,
                    ),
                  )
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tagged) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tagIcon(message.tag), size: 13, color: tc.ink),
                      const SizedBox(width: 5),
                      Text(tagLabel(message.tag).toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: tc.ink)),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (message.documentId != null)
                  _AttachmentChip(
                      documentId: message.documentId!, onDark: isMine),
                // A message can be an attachment with no text at all, so the
                // body only takes space when there is one.
                if ((message.body ?? '').trim().isNotEmpty) ...[
                  if (message.documentId != null) const SizedBox(height: 7),
                  Text(
                    message.body!,
                    style:
                        TextStyle(fontSize: 13.5, color: fg, height: 1.35),
                  ),
                ],
              ],
            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
                ),
                if (isMine && !message.isDeleted) ...[
                  const SizedBox(width: 4),
                  AuditedStatusCheck(
                    state: readByOther
                        ? MessageReceiptState.read
                        : MessageReceiptState.sent,
                    size: 12,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final MessageTag tag;
  final ValueChanged<MessageTag> onTagChanged;
  const _Composer(
      {required this.controller,
      required this.sending,
      required this.onSend,
      required this.onAttach,
      required this.tag,
      required this.onTagChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
        // Three buttons, not four: blue is what a message already is, so there
        // is nothing to press for it. Each one toggles, so the same tap takes
        // it back off.
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              for (final t in [
                MessageTag.pending,
                MessageTag.invoice,
                MessageTag.urgent
              ]) ...[
                _TagButton(
                  tag: t,
                  selected: tag == t,
                  onTap: sending
                      ? null
                      : () => onTagChanged(tag == t ? MessageTag.normal : t),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: sending ? null : onAttach,
              icon: Icon(Icons.attach_file, color: AppColors.inkMuted),
              tooltip: 'Attach a photo',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message…',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : Icon(Icons.send, color: AppColors.primary),
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }
}

class _TagButton extends StatelessWidget {
  final MessageTag tag;
  final bool selected;
  final VoidCallback? onTap;
  const _TagButton(
      {required this.tag, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = tagColours(tag);
    return Expanded(
      child: Material(
        color: selected ? c.bg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(
                  color: selected ? c.ink : AppColors.border,
                  width: selected ? 1.2 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tagIcon(tag),
                    size: 14, color: selected ? c.ink : AppColors.inkSubtle),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    tagLabel(tag),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? c.ink : AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An attachment inside a bubble. The signed URL is minted only when tapped,
/// so opening a thread does not create URLs for files nobody looks at.
class _AttachmentChip extends StatefulWidget {
  final String documentId;
  final bool onDark;
  const _AttachmentChip({required this.documentId, required this.onDark});

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  final _docs = DocumentService();
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final doc = await _docs.getSignedUrl(widget.documentId);
      if (!mounted) return;
      if (doc.mimeType.startsWith('image/')) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _ChatImageViewer(url: doc.url, filename: doc.filename),
        ));
      } else {
        // PDFs and anything else hand off to the system viewer, the same
        // split documents_screen.dart already uses.
        await launchUrl(Uri.parse(doc.url),
            mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the file: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.onDark ? Colors.white : AppColors.ink;
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.onDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else
              Icon(Icons.attach_file, size: 15, color: fg),
            const SizedBox(width: 8),
            Text('Attachment',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _ChatImageViewer extends StatelessWidget {
  final String url;
  final String filename;
  const _ChatImageViewer({required this.url, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(filename,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(url,
              errorBuilder: (_, _, _) => const Text('Could not load the image',
                  style: TextStyle(color: Colors.white70))),
        ),
      ),
    );
  }
}
