import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/team_channel_screen.dart';
import '../services/team_channel_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// Whether this workspace gets the Team channel at all: only a firm's own
/// members. Never a client's portal, never a personal or basic workspace (those
/// are not firms). The database enforces the same rule.
bool workspaceHasTeamChat(Workspace w) => w.isFirm && !w.isPortalClient;

/// The Team button: a small pill with the unread count on top of it. Shown in
/// the chat inbox AND inside an open client conversation, so the badge keeps
/// showing while a client chat is open. Keeps its own count fresh (realtime,
/// coming back to the app, coming back from the channel).
class TeamButton extends StatefulWidget {
  final Workspace workspace;
  const TeamButton({super.key, required this.workspace});

  @override
  State<TeamButton> createState() => _TeamButtonState();
}

class _TeamButtonState extends State<TeamButton> with WidgetsBindingObserver {
  final _service = TeamChannelService();
  RealtimeChannel? _channel;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final n = await _service.unreadCount(widget.workspace.orgId);
      if (mounted) setState(() => _unread = n);
    } catch (_) {
      // Keep showing the last count rather than flashing an error on a badge.
    }
  }

  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('team-button-${widget.workspace.orgId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'workspace_team_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'org_id',
            value: widget.workspace.orgId,
          ),
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamChannelScreen(workspace: widget.workspace),
      ),
    );
    // Reading it in there cleared the count; pick that up.
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: Tooltip(
          message: _unread > 0 ? 'Team chat — $_unread unread' : 'Team chat',
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: _open,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Team',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_unread > 0)
                  Positioned(
                    top: -7,
                    right: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: AppColors.surface, width: 1.5),
                      ),
                      child: Text(
                        _unread > 99 ? '99+' : '$_unread',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
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
