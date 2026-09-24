import 'package:flutter/material.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/chat_bubble_overlay.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'review_screen.dart';
import 'work_screen.dart';

/// The 5-tab shell from the mobile UX design: Home / Review / Capture (a
/// sheet, not a page -- index 2 is a no-op tap target) / Work / More.
class AppShell extends StatefulWidget {
  final Workspace workspace;

  /// Every workspace the user can reach, plus whether the Firm/Personal switch
  /// applies to them at all. Only Home renders the switch; the other tabs just
  /// follow whichever workspace is active.
  final WorkspaceScope scope;
  final Future<void> Function(Workspace) onSwitch;
  final Future<void> Function() onCreatePersonal;

  const AppShell({
    super.key,
    required this.workspace,
    required this.scope,
    required this.onSwitch,
    required this.onCreatePersonal,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        workspace: widget.workspace,
        scope: widget.scope,
        onSwitch: widget.onSwitch,
        onCreatePersonal: widget.onCreatePersonal,
      ),
      ReviewScreen(workspace: widget.workspace),
      const SizedBox.shrink(), // Capture has no page -- handled in onTap below
      WorkScreen(workspace: widget.workspace),
      MoreScreen(workspace: widget.workspace),
    ];

    return Scaffold(
      body: ChatBubbleOverlay(
        workspace: widget.workspace,
        child: IndexedStack(index: _index == 2 ? 0 : _index, children: pages),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index == 2 ? 0 : _index,
        onTap: (i) {
          if (i == 2) {
            showCaptureSheet(context, workspace: widget.workspace);
            return;
          }
          setState(() => _index = i);
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), activeIcon: Icon(Icons.insights), label: 'Review'),
          BottomNavigationBarItem(
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.add, size: 16, color: Colors.white),
            ),
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.work_outline), activeIcon: Icon(Icons.work), label: 'Work'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
