import 'package:flutter/material.dart';
import '../screens/bills_screen.dart';
import '../screens/invoices_screen.dart';
import '../screens/manual_expense_screen.dart';
import '../screens/receipt_capture_screen.dart';
import '../screens/timer_screen.dart';
import '../screens/transactions_screen.dart';
import '../screens/trip_tracker_screen.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import 'client_picker_sheet.dart';

/// The center "+" tab's bottom sheet -- equal action cards, per the mobile UX
/// design (Capture is a sheet, not a screen). Mileage tracking and receipt OCR
/// have real backends already (mileage_connections/-webhook, ocr-receipt).
///
/// [id] is what the Home quick-actions row saves (see utils/quick_action_prefs
/// .dart), so an action keeps its identity even if its label is reworded.
class CaptureAction {
  final String id;
  final IconData icon;
  final String label;

  /// One word for the small card on Home.
  final String shortLabel;
  const CaptureAction(this.id, this.icon, this.label, this.shortLabel);
}

const captureActions = [
  CaptureAction('scan_receipt', Icons.camera_alt_outlined, 'Scan receipt', 'Receipt'),
  CaptureAction('log_time', Icons.timer_outlined, 'Log time', 'Time'),
  CaptureAction('log_trip', Icons.navigation_outlined, 'Log a trip', 'Trip'),
  CaptureAction('manual_expense', Icons.edit_outlined, 'Manual expense', 'Expense'),
  // The Transactions dashboard: every bank and manual transaction with the
  // semaphore filter. It is a place to look, not something to capture, but it
  // is the first thing people reach for after capturing one.
  CaptureAction('transactions', Icons.receipt_long_outlined, 'Transactions', 'Transactions'),
];

/// What Capture offers in the workspace you are actually in.
///
/// Mileage is dropped in firm mode, for the same reason bank connections are:
/// a trip is a deduction against one set of books, and a firm workspace is not
/// one. An accountant logs their own driving in their personal workspace. The
/// filter lives here because both the Capture sheet and the Home quick-action
/// row read this list, and a rule written twice is a rule that drifts.
List<CaptureAction> captureActionsFor(Workspace workspace) {
  if (workspace.category != OrgCategory.firm) return captureActions;
  return captureActions.where((a) => a.id != 'log_trip').toList();
}

/// In a firm workspace, a receipt has to belong to a client -- there is no
/// such thing as an unscoped receipt when the accountant manages several
/// clients' books at once (same rule bank connections already follow). A
/// personal workspace has nothing to pick, so it skips straight to the
/// camera. A portal-client workspace also skips the picker (there's only
/// ever one answer: themselves) but real bug found in the mobile audit:
/// this used to leave clientId null even then, and register_document's own
/// authorization requires a non-null, matching client_id for a caller with
/// no organization_memberships row -- every receipt a portal client scanned
/// failed with "unauthorized: not a member of this org or client".
Future<void> _openReceiptCapture(BuildContext context, Workspace workspace) async {
  if (workspace.category != OrgCategory.firm) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ReceiptCaptureScreen(workspace: workspace, clientId: workspace.portalClientId),
    ));
    return;
  }
  final client = await pickClient(context, orgId: workspace.orgId);
  if (client == null || !context.mounted) return;
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ReceiptCaptureScreen(workspace: workspace, clientId: client.id, clientName: client.displayName),
  ));
}

/// Opens the screen behind an action id. The ONE place that maps an id to a
/// screen, used by the Capture sheet and the Home quick-actions row alike: Home
/// used to open the receipt camera directly, which skipped the client picker a
/// firm needs.
void openQuickAction(BuildContext context, String id, Workspace workspace) {
  Widget? screen;
  switch (id) {
    case 'scan_receipt':
      _openReceiptCapture(context, workspace);
      return;
    case 'log_time':
      screen = TimerScreen(workspace: workspace);
    case 'log_trip':
      screen = TripTrackerScreen(workspace: workspace);
    case 'manual_expense':
      screen = ManualExpenseScreen(workspace: workspace);
    case 'transactions':
      screen = TransactionsScreen(workspace: workspace);
    case 'invoices':
      screen = InvoicesScreen(workspace: workspace);
    case 'bills':
      screen = BillsScreen(workspace: workspace);
  }
  if (screen == null) return;
  final target = screen;
  Navigator.push(context, MaterialPageRoute(builder: (_) => target));
}

void showCaptureSheet(BuildContext context, {required Workspace workspace}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(100)),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Capture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: captureActionsFor(workspace).map((a) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  openQuickAction(context, a.id, workspace);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(a.icon, color: AppColors.primaryInk, size: 22),
                      const SizedBox(height: 6),
                      Text(a.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
}
