import 'package:flutter/material.dart';
import '../services/sales_tax_service.dart';
import '../theme/app_theme.dart';

/// One line under the client that says what sales tax applies and lets the
/// person accept it in a tap -- so the percentage is never typed by hand.
/// Shows nothing while there is nothing useful to say.
class SalesTaxBar extends StatelessWidget {
  final SalesTaxSuggestion? suggestion;
  final bool loading;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  const SalesTaxBar({
    super.key,
    required this.suggestion,
    required this.loading,
    required this.applied,
    required this.onApply,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6)),
          const SizedBox(width: 8),
          Text('Looking up sales tax…',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ]),
      );
    }
    final s = suggestion;
    if (s == null) return const SizedBox.shrink();

    final rate = s.rate;
    if (rate == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(s.reason ?? '',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
      );
    }

    final pct = rate.ratePct == rate.ratePct.roundToDouble()
        ? rate.ratePct.toStringAsFixed(0)
        : rate.ratePct.toString();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: applied ? AppColors.greenBg : AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(applied ? Icons.check_circle_outline : Icons.calculate_outlined,
              size: 18, color: applied ? AppColors.green : AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              applied
                  ? 'Sales tax $pct% applied · ${rate.jurisdiction}'
                  : 'Sales tax for ${rate.stateCode}: $pct%',
              style: TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
          TextButton(
            onPressed: applied ? onRemove : onApply,
            child: Text(applied ? 'Remove' : 'Apply'),
          ),
        ],
      ),
    );
  }
}
