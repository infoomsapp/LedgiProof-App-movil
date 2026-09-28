import 'package:flutter/material.dart';
import '../services/report_service.dart';
import '../theme/app_theme.dart';
import '../utils/doc_format.dart';

/// Owed to you, you owe, cash and this month's profit -- the web dashboard's
/// snapshot tiles, from the same RPC. Shows nothing when the snapshot cannot
/// be read, so it never gets in the way of Home. The For review count is
/// already Home's headline, so it is not repeated here.
///
/// In a firm client's books ([clientScope]) there are no invoices or bills,
/// so only cash and profit show.
class BooksSnapshotCard extends StatelessWidget {
  final Future<BooksSnapshot?> future;
  final bool clientScope;
  const BooksSnapshotCard({super.key, required this.future, this.clientScope = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BooksSnapshot?>(
      future: future,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const SizedBox.shrink();
        final tiles = <Widget>[
          if (!clientScope) ...[
            _Tile(
              label: 'Owed to you',
              value: s.owedToYou,
              color: AppColors.green,
              sub: s.owedOverdue > 0 ? '${formatMoney(s.owedOverdue)} overdue' : null,
            ),
            _Tile(
              label: 'You owe',
              value: s.youOwe,
              color: AppColors.red,
              sub: s.youOweOverdue > 0 ? '${formatMoney(s.youOweOverdue)} overdue' : null,
            ),
          ],
          _Tile(label: 'Cash', value: s.cash, color: AppColors.ink),
          _Tile(
            label: 'Profit this month',
            value: s.monthProfit,
            color: s.monthProfit >= 0 ? AppColors.green : AppColors.red,
            sub: 'Last month ${formatMoney(s.lastMonthProfit)}',
          ),
        ];
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: tiles,
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String? sub;
  const _Tile({required this.label, required this.value, required this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatMoney(value),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color)),
          ),
          if (sub != null)
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}
