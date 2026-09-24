import 'package:flutter/material.dart';
import '../screens/chat_thread_screen.dart';
import '../screens/documents_screen.dart';
import '../screens/invoice_compose_screen.dart';
import '../services/invoice_service.dart';
import '../services/books_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// What tapping a client in the Work tab offers.
///
/// The Work tab already drew a chevron on every client row and imported this
/// file, but the file was never written and the rows had no onTap at all --
/// the list looked tappable and did nothing. This is that missing half.
///
/// Both actions are scoped to the client that was tapped: the chat thread is
/// the workspace conversation with them, and Documents is filtered to their
/// files rather than the whole firm's.
void showClientActionSheet(
  BuildContext context, {
  required Workspace workspace,
  required ClientSummary client,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.displayName,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                ),
                if (client.companyName != null) ...[
                  const SizedBox(height: 2),
                  Text(client.companyName!,
                      style:
                          TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ],
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          _Action(
            icon: Icons.chat_bubble_outline,
            label: 'Message',
            subtitle: 'Your conversation with this client',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatThreadScreen(
                  workspace: workspace,
                  // Deliberately null: the thread may not exist yet, and the
                  // first message creates it server-side.
                  clientId: client.id,
                  clientName: client.displayName,
                ),
              ));
            },
          ),
          if (!workspace.isPortalClient &&
              InvoiceService.canCreateInvoices(workspace.role)) ...[
            Divider(height: 1, thickness: 1, color: AppColors.border),
            _Action(
              icon: Icons.receipt_long_outlined,
              label: 'New invoice',
              subtitle: 'Bill this client',
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InvoiceComposeScreen(
                      workspace: workspace, client: client),
                ));
              },
            ),
          ],
          Divider(height: 1, thickness: 1, color: AppColors.border),
          _Action(
            icon: Icons.folder_outlined,
            label: 'Documents',
            subtitle: 'Files shared with this client',
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DocumentsScreen(
                  orgId: workspace.orgId,
                  clientId: client.id,
                  title: client.displayName,
                ),
              ));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppColors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.inkSubtle)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.inkSubtle),
          ],
        ),
      ),
    );
  }
}
