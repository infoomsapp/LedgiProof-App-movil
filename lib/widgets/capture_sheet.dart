import 'package:flutter/material.dart';
import '../screens/timer_screen.dart';
import '../screens/trip_tracker_screen.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// The center "+" tab's bottom sheet -- four equal actions, per the mobile
/// UX design (Capture is a sheet, not a screen). Mileage tracking and
/// receipt OCR have real backends already (mileage_connections/-webhook,
/// ocr-receipt) but their mobile screens aren't built yet in this first
/// shell pass -- tapping them says so honestly instead of pretending.
class CaptureAction {
  final IconData icon;
  final String label;
  const CaptureAction(this.icon, this.label);
}

const captureActions = [
  CaptureAction(Icons.camera_alt_outlined, 'Scan receipt'),
  CaptureAction(Icons.timer_outlined, 'Log time'),
  CaptureAction(Icons.navigation_outlined, 'Log a trip'),
  CaptureAction(Icons.edit_outlined, 'Manual expense'),
];

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
          const Align(
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
            children: captureActions.map((a) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  if (a.label == 'Log time') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TimerScreen(workspace: workspace)));
                    return;
                  }
                  if (a.label == 'Log a trip') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TripTrackerScreen(workspace: workspace)));
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${a.label} — coming in the next build pass')),
                  );
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
                      Text(a.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
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
