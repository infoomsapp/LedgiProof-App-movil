import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/team_channel_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/chat_merge.dart';
import '../utils/errors.dart';

/// The firm's team channel: one channel per firm, only its own members (never
/// clients). Same look as a client thread, minus everything client-facing (no
/// tags, no attachments, no receipts). Everyone -- owner and admin included --
/// deletes only their OWN messages.
///
/// Same recovery rules as the client thread: the list is never swapped for a
/// spinner after the first load, a failed reload keeps the last good list, and
/// every "we may have missed something" moment (coming back to the app, the
/// realtime socket reconnecting) reloads the latest page and MERGES it into
/// what is on screen.
class TeamChannelScreen extends StatefulWidget {
  final Workspace workspace;
  const TeamChannelScreen({super.key, required this.workspace});

  @override
  State<TeamChannelScreen> createState() => _TeamChannelScreenState();
}

class _TeamChannelScreenState extends State<TeamChannelScreen>
    with WidgetsBindingObserver {
  final _service = TeamChannelService();
  final _controller = TextEditingController();
  late Future<TeamChannelPage> _future;
  RealtimeChannel? _channel;
  bool _subscribedBefore = false;

  List<TeamMessage> _all = const [];
  bool _hasMore = false;
  String? _oldestAt;
  bool _loadedOnce = false;
  bool _loadingOlder = false;
  bool _sending = false;
  int _loadSeq = 0;

  String get _orgId => widget.workspace.orgId;
  String? get _myUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
    _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _reload();
  }

  /// True only while this channel is what the person is looking at: app in the
  /// foreground AND no other route (screen, dialog, sheet) on top of it.
  bool get _isInFront {
    final life = WidgetsBinding.instance.lifecycleState;
    final foreground = life == null || life == AppLifecycleState.resumed;
    return foreground && mounted && (ModalRoute.of(context)?.isCurrent ?? false);
  }

  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('team-channel-$_orgId')
        .onPostgresChanges(
          // INSERT = a new message; UPDATE = the sender deleted theirs.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_team_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'org_id',
            value: _orgId,
          ),
          callback: (_) {
            if (mounted) _reload();
          },
        )
        .subscribe((status, _) {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          // First "subscribed" is the initial connect; a later one is a
          // reconnect and events may have been lost in the gap.
          if (_subscribedBefore && mounted) _reload();
          _subscribedBefore = true;
        });
  }

  Future<TeamChannelPage> _load() async {
    final seq = ++_loadSeq;
    final res = await _service.getChannel(_orgId);
    if (seq == _loadSeq) {
      final merged = mergeLatestPage<TeamMessage>(
        _all,
        res.messages,
        res.hasMore,
        (m) => m.id,
      );
      _all = merged.messages;
      if (!merged.keptOlder) {
        _hasMore = res.hasMore;
        _oldestAt = res.oldestAt;
      }
      _loadedOnce = true;
      // Read as soon as it is on screen -- but only if the person is really
      // looking at it, never from the background.
      if (res.unreadCount > 0 && _isInFront) {
        unawaited(_service.markRead(_orgId).catchError((_) {}));
      }
    }
    return res;
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _loadOlder() async {
    final before = _oldestAt;
    if (before == null || _loadingOlder || !_hasMore) return;
    setState(() => _loadingOlder = true);
    try {
      final res = await _service.getChannel(_orgId, before: before);
      if (!mounted) return;
      final have = _all.map((m) => m.id).toSet();
      setState(() {
        _all = [...res.messages.where((m) => !have.contains(m.id)), ..._all];
        _hasMore = res.hasMore;
        _oldestAt = res.oldestAt ?? _oldestAt;
        _loadingOlder = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      _snack('Could not load older messages: ${friendlyError(e)}');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.send(_orgId, text);
      _controller.clear(); // only once it is safely sent: never lose the text
      _reload();
    } catch (e) {
      _snack('Could not send: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteMine(TeamMessage m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text('It disappears for your whole team.'),
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
    if (confirmed != true) return;
    try {
      await _service.deleteMine(m.id);
      _reload();
    } catch (e) {
      _snack('Could not delete: ${friendlyError(e)}');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Team',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              "Only your firm's team can see this",
              style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<TeamChannelPage>(
              future: _future,
              builder: (context, snap) {
                if (!_loadedOnce &&
                    snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!_loadedOnce && snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load the team chat.',
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                        TextButton(
                          onPressed: _reload,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }
                final messages = _all;
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No messages yet. Start the conversation with your team.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == messages.length) {
                      return Center(
                        child: TextButton(
                          onPressed: _loadingOlder ? null : _loadOlder,
                          child: Text(
                            _loadingOlder ? 'Loading…' : 'Load older messages',
                          ),
                        ),
                      );
                    }
                    // Server returns oldest-first; render newest-first without
                    // re-sorting by walking the list backwards.
                    final m = messages[messages.length - 1 - i];
                    final isMine = m.senderId != null && m.senderId == _myUserId;
                    return _TeamBubble(
                      message: m,
                      isMine: isMine,
                      // Own messages only, for everyone.
                      onDelete: (isMine && !m.isDeleted) ? () => _deleteMine(m) : null,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message your team…',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamBubble extends StatelessWidget {
  final TeamMessage message;
  final bool isMine;
  final VoidCallback? onDelete;
  const _TeamBubble({
    required this.message,
    required this.isMine,
    required this.onDelete,
  });

  String _time(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isMine ? AppColors.primary : AppColors.surface;
    final fg = isMine ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMine && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4),
              child: Text(
                message.senderName!,
                style: TextStyle(fontSize: 11, color: AppColors.inkSubtle),
              ),
            ),
          GestureDetector(
            onLongPress: onDelete,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(
                  color: isMine ? Colors.transparent : AppColors.border,
                ),
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
                  : Text(
                      message.body ?? '',
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: fg),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(
              _time(message.createdAt),
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
            ),
          ),
        ],
      ),
    );
  }
}
