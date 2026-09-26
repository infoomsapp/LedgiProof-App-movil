import 'package:flutter/material.dart';
import '../services/tax_snapshot_service.dart';
import '../theme/app_theme.dart';
import '../utils/doc_format.dart';

/// The sales-tax record of an issued invoice, for the firm. Loads itself and
/// shows nothing when there is no snapshot or it cannot be read, so it can
/// never get in the way of the invoice.
class TaxSnapshotCard extends StatefulWidget {
  final String invoiceId;
  final double currentTaxTotal;
  final String currency;
  const TaxSnapshotCard({
    super.key,
    required this.invoiceId,
    required this.currentTaxTotal,
    required this.currency,
  });

  @override
  State<TaxSnapshotCard> createState() => _TaxSnapshotCardState();
}

class _TaxSnapshotCardState extends State<TaxSnapshotCard> {
  late final Future<TaxSnapshot?> _future =
      TaxSnapshotService().forInvoice(widget.invoiceId).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TaxSnapshot?>(
      future: _future,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const SizedBox.shrink();

        final (icon, color, bg) = switch (s.status) {
          TaxSnapshotStatus.matchesReference =>
            (Icons.verified_outlined, AppColors.green, AppColors.greenBg),
          TaxSnapshotStatus.manualOverride =>
            (Icons.tune, AppColors.amber, AppColors.amberBg),
          TaxSnapshotStatus.requiresReview =>
            (Icons.flag_outlined, AppColors.red, AppColors.redBg),
          TaxSnapshotStatus.noTax =>
            (Icons.remove_circle_outline, AppColors.inkMuted, AppColors.surface2),
        };
        final changed = s.changedSinceIssue(widget.currentTaxTotal);

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.headline,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                      const SizedBox(height: 3),
                      Text(s.detail,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.inkMuted)),
                      if (changed) ...[
                        const SizedBox(height: 6),
                        Text(
                            'The tax on this invoice changed after it was issued: '
                            '${formatMoney(s.taxTotal, currency: widget.currency)} '
                            'then, ${formatMoney(widget.currentTaxTotal, currency: widget.currency)} now.',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.amber)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
