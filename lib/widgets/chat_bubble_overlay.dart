import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/chat_inbox_screen.dart';
import '../services/workspace_chat_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/chat_ring.dart';
import 'lp_chat_brand_icon.dart';

/// A draggable floating chat bubble, always on top of [child], mirroring the
/// web's GlobalChatBubble.tsx: same ring rule (see utils/chat_ring.dart: grey
/// = nothing unread, blue = normal, green = invoice, amber = outstanding,
/// red = needs a reply), same unread badge. Only ever shown for
/// a workspace that actually has chat -- a personal ("started") workspace has
/// no client relationship for chat to scope to, so the bubble stays absent
/// there rather than opening onto an empty inbox.
class ChatBubbleOverlay extends StatefulWidget {
  final Workspace workspace;
  final Widget child;
  const ChatBubbleOverlay({super.key, required this.workspace, required this.child});

  @override
  State<ChatBubbleOverlay> createState() => _ChatBubbleOverlayState();
}

class _ChatBubbleOverlayState extends State<ChatBubbleOverlay> {
  static const _bubbleSize = 56.0;
  static const _posXKey = 'ledgiproof_chat_bubble_x'; // fraction 0..1 of usable width
  static const _posYKey = 'ledgiproof_chat_bubble_y'; // fraction 0..1 of usable height

  final _service = WorkspaceChatService();
  Timer? _pollTimer;
  RealtimeChannel? _channel;

  static const _edgeMargin = 12.0;

  WorkspaceInboxResponse? _inbox;
  double? _xFrac;
  double? _yFrac;

  // Raw pixel position followed live while a drag is in progress -- see
  // build() for why this, not the fraction fields, drives the bubble while
  // _dragging is true.
  bool _dragging = false;
  double? _dragX;
  double? _dragY;

  bool get _hasChat => widget.workspace.isFirm || widget.workspace.isPortalClient;

  @override
  void initState() {
    super.initState();
    if (_hasChat) {
      _restorePosition();
      _refreshInbox();
      _subscribeRealtime();
      _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshInbox());
    }
  }

  @override
  void didUpdateWidget(covariant ChatBubbleOverlay old) {
    super.didUpdateWidget(old);
    if (old.workspace.orgId != widget.workspace.orgId ||
        old.workspace.portalClientId != widget.workspace.portalClientId) {
      _channel?.unsubscribe();
      _pollTimer?.cancel();
      _inbox = null;
      if (_hasChat) {
        _refreshInbox();
        _subscribeRealtime();
        _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshInbox());
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_posXKey);
      final y = prefs.getDouble(_posYKey);
      if (mounted) setState(() { _xFrac = x; _yFrac = y; });
    } catch (_) {
      // Defaults to the bottom-right corner below.
    }
  }

  Future<void> _savePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_xFrac != null) await prefs.setDouble(_posXKey, _xFrac!);
      if (_yFrac != null) await prefs.setDouble(_posYKey, _yFrac!);
    } catch (_) {
      // A lost position just falls back to the default corner next launch.
    }
  }

  Future<void> _refreshInbox() async {
    try {
      final res = await _service.getInbox(widget.workspace.orgId);
      if (mounted) setState(() => _inbox = res);
    } catch (_) {
      // Keep showing whatever we last had rather than flashing an error ring.
    }
  }

  /// Same Realtime pattern as useWorkspaceChat.ts: subscribe to inserts on
  /// the workspace_messages table (RLS narrows to what this session can see)
  /// and refresh when the app is in the foreground. The 60s Timer above is
  /// the polling fallback for when Realtime is briefly unavailable.
  void _subscribeRealtime() {
    final db = Supabase.instance.client;
    _channel = db
        .channel('workspace-chat-bubble-${widget.workspace.orgId}')
        .onPostgresChanges(
          // All events, not just inserts: a message being READ (here or on
          // another device) must clear the ring too, not wait for the 60 s poll.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workspace_messages',
          callback: (_) => _refreshInbox(),
        )
        // A team-channel message changes the badge, which rides on the inbox
        // response. RLS only lets a firm's own members receive these.
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'workspace_team_messages',
          callback: (_) => _refreshInbox(),
        )
        .subscribe();
  }

  _Semaphore _semaphore() {
    final r = chatRing(
      _inbox?.conversations ?? const [],
      teamUnread: _inbox?.teamUnread ?? 0,
    );
    final color = switch (r.tag) {
      null => AppColors.border,
      MessageTag.urgent => AppColors.red,
      MessageTag.pending => AppColors.amber,
      MessageTag.invoice => AppColors.green,
      MessageTag.normal => AppColors.primary,
    };
    return _Semaphore(color, r.label);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasChat) return widget.child;

    // LayoutBuilder wraps the WHOLE Stack here rather than sitting inside
    // Stack.children -- that was the actual bug behind the bubble never
    // moving. Positioned/AnimatedPositioned only take effect when they are
    // the DIRECT widget child of a Stack; LayoutBuilder is itself a
    // RenderObjectWidget (it has its own RenderObject in the tree), so an
    // AnimatedPositioned returned from a LayoutBuilder that is ITSELF one of
    // Stack's children ends up parented under that LayoutBuilder's render
    // object instead of under RenderStack directly. RenderStack then never
    // sees the StackParentData at all and lays the bubble out as an
    // ordinary non-positioned child, pinned by Stack's default alignment --
    // which looks exactly like "the bubble is static," because every drag
    // update was being applied to a parent data object RenderStack never
    // reads. With LayoutBuilder as the outer widget, the Stack it returns
    // is a real Stack literal here, and AnimatedPositioned is its direct
    // child, so this is fixed structurally, not with a workaround.
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final maxX = size.width - _bubbleSize;
      final maxY = size.height - _bubbleSize;
      final settledX = _xFrac != null
          ? (_xFrac! * maxX).clamp(0.0, maxX)
          : maxX - _edgeMargin;
      final settledY = _yFrac != null
          ? (_yFrac! * maxY).clamp(0.0, maxY)
          : maxY - 80;

      // While dragging, the bubble follows the finger exactly (duration
      // zero -- any easing here would make it visibly lag the touch point).
      // On release it snaps to the nearest horizontal edge with a short
      // eased animation, the same "drag freely, snap home on release" feel
      // Messenger's chat heads use, without needing that feature's
      // system-level overlay (this bubble only ever floats within the app,
      // per how it was asked for).
      final x = _dragging ? (_dragX ?? settledX) : settledX;
      final y = _dragging ? (_dragY ?? settledY) : settledY;

      return Stack(
        children: [
          widget.child,
          AnimatedPositioned(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: x,
            top: y,
            child: GestureDetector(
              onPanStart: (_) {
                setState(() {
                  _dragging = true;
                  _dragX = settledX;
                  _dragY = settledY;
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  _dragX = ((_dragX ?? settledX) + details.delta.dx).clamp(0.0, maxX);
                  _dragY = ((_dragY ?? settledY) + details.delta.dy).clamp(0.0, maxY);
                });
              },
              onPanEnd: (_) {
                final endX = _dragX ?? settledX;
                final endY = _dragY ?? settledY;
                final snappedX = (endX + _bubbleSize / 2) < size.width / 2
                    ? _edgeMargin
                    : maxX - _edgeMargin;
                setState(() {
                  _dragging = false;
                  _xFrac = maxX > 0 ? (snappedX.clamp(0.0, maxX)) / maxX : 0;
                  _yFrac = maxY > 0 ? endY / maxY : 0;
                });
                _savePosition();
              },
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatInboxScreen(workspace: widget.workspace),
                ));
                _refreshInbox();
              },
              child: _Bubble(
                unread: (_inbox?.unreadTotal ?? 0) + (_inbox?.teamUnread ?? 0),
                semaphore: _semaphore(),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _Semaphore {
  final Color ring;
  final String label;
  _Semaphore(this.ring, this.label);
}

class _Bubble extends StatelessWidget {
  final int unread;
  final _Semaphore semaphore;
  const _Bubble({required this.unread, required this.semaphore});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: semaphore.label,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
          border: Border.all(color: semaphore.ring, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(child: LpChatBrandIcon(size: 40)),
            if (unread > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: semaphore.ring,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
