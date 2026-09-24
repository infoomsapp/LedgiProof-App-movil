import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import 'checklists_screen.dart';
import 'connections_screen.dart';
import 'settings_screen.dart';
import 'timer_screen.dart';

/// The overflow tab. Every row here used to answer with a "coming in the next
/// build pass" snackbar; they now open real screens. Time reuses the timer that
/// already existed behind the Capture sheet rather than a second copy of it.
class MoreScreen extends StatelessWidget {
  final Workspace workspace;
  const MoreScreen({super.key, required this.workspace});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('More',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _MoreRow(
            icon: Icons.checklist_outlined,
            label: 'Checklists',
            subtitle: 'Open runs and their items',
            onTap: () => _open(context, ChecklistsScreen(workspace: workspace)),
          ),
          _MoreRow(
            icon: Icons.schedule_outlined,
            label: 'Time',
            subtitle: 'Start or stop a time entry',
            onTap: () => _open(context, TimerScreen(workspace: workspace)),
          ),
          // Available in every workspace, because what it shows differs by
          // workspace rather than being allowed or forbidden: in firm mode it
          // lists the CLIENTS' accounts the firm looks after, and in a personal
          // or client workspace it lists that workspace's own. The database
          // already draws this line (bank_conn_select for org members,
          // bank_connections_client_select for a client user), so the screen
          // only has to say whose accounts these are.
          _MoreRow(
            icon: Icons.link_outlined,
            label: 'Connections',
            subtitle: workspace.category == OrgCategory.firm
                ? 'Client bank accounts'
                : 'Linked bank accounts',
            onTap: () =>
                _open(context, ConnectionsScreen(workspace: workspace)),
          ),
          _MoreRow(
            icon: Icons.settings_outlined,
            label: 'Settings',
            subtitle: 'Appearance and account',
            onTap: () => _open(context, SettingsScreen(workspace: workspace)),
          ),
          const SizedBox(height: 8),
          _MoreRow(
            icon: Icons.logout,
            label: 'Sign out',
            destructive: true,
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _MoreRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: destructive ? AppColors.red : AppColors.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: color)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkSubtle)),
                    ],
                  ],
                ),
              ),
              if (!destructive)
                Icon(Icons.chevron_right, size: 16, color: AppColors.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
