import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/bill_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lp_chat_brand_icon.dart';
import 'add_accountant_screen.dart';
import 'bills_screen.dart';
import 'chat_inbox_screen.dart';
import 'checklists_screen.dart';
import 'connections_screen.dart';
import 'notes_screen.dart';
import 'reports_screen.dart';
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
          // Checklists are the firm's own work: a client of a firm is not a
          // member of the organization, so the database shows them nothing and
          // the row would only lead to an empty screen.
          if (!workspace.isPortalClient)
            _MoreRow(
              icon: Icons.checklist_outlined,
              label: 'Checklists',
              subtitle: 'Create, work through and schedule',
              onTap: () => _open(context, ChecklistsScreen(workspace: workspace)),
            ),
          // Firm notes are internal to the firm's staff (RLS: org members
          // only), so neither a portal client nor a personal workspace sees it.
          if (workspace.isFirm && !workspace.isPortalClient)
            _MoreRow(
              icon: Icons.sticky_note_2_outlined,
              label: 'Notes',
              subtitle: 'Client notes, approvals and reminders',
              onTap: () => _open(context, NotesScreen(workspace: workspace)),
            ),
          _MoreRow(
            icon: Icons.schedule_outlined,
            label: 'Time',
            subtitle: 'Start or stop a time entry',
            onTap: () => _open(context, TimerScreen(workspace: workspace)),
          ),
          // Chat is scoped to a client relationship under a firm's org, which
          // a personal workspace never has -- there is no conversation for it
          // to show. Personal gets "Add an accountant" instead: the closest
          // honest equivalent, since a solo user cannot self-grant org
          // membership to anyone (real access is always created from the
          // firm's side, via AddClientDialog on the web).
          if (workspace.isFirm || workspace.isPortalClient)
            _MoreRow(
              icon: Icons.chat_bubble_outline,
              leadingWidget: const LpChatBrandIcon(size: 22),
              label: 'Chat',
              subtitle: workspace.isFirm ? 'Message your clients' : 'Message your accountant',
              onTap: () => _open(context, ChatInboxScreen(workspace: workspace)),
            )
          else if (workspace.category == OrgCategory.personal)
            _MoreRow(
              icon: Icons.person_add_alt_outlined,
              label: 'Add an accountant',
              subtitle: 'Invite one to manage these books',
              onTap: () => _open(context, AddAccountantScreen(workspace: workspace)),
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
          // Vendor bills belong to a firm's own staff: the vendor_bills
          // policies want owner/admin/accountant, and a client of a firm holds
          // no org role. Whether the plan includes bill tracking is checked
          // when the screen opens.
          if (workspace.isFirm &&
              !workspace.isPortalClient &&
              BillService.canManageBills(workspace.role))
            _MoreRow(
              icon: Icons.request_quote_outlined,
              label: 'Bills',
              subtitle: 'What you owe vendors, and when',
              onTap: () => _open(context, BillsScreen(workspace: workspace)),
            ),
          // A client of a firm reads their books through the portal, where the
          // firm decides what is published; org-level reports are the firm's
          // own view, so this row belongs to staff.
          if (!workspace.isPortalClient)
            _MoreRow(
              icon: Icons.insights_outlined,
              label: 'Reports',
              subtitle: 'P&L and Balance Sheet',
              onTap: () => _open(context, ReportsScreen(workspace: workspace)),
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
  final Widget? leadingWidget;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.leadingWidget,
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
              leadingWidget ??
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
