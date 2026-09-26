import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/doc_format.dart';

/// What sales tax an invoice was issued with and how that compares with the
/// reference rate for the billing address on the issue date. Written once by
/// the database when the invoice leaves draft; never edited.

enum TaxSnapshotStatus { matchesReference, manualOverride, requiresReview, noTax }

class ChargedRate {
  final double rate;
  final double taxableAmount;
  final double taxAmount;
  const ChargedRate(this.rate, this.taxableAmount, this.taxAmount);
}

class TaxSnapshot {
  final TaxSnapshotStatus status;
  final String? reason;
  final String? destinationState;
  final double? referenceRate;
  final String? referenceJurisdiction;
  final String? referenceSource;
  final DateTime? referenceEffectiveFrom;
  final DateTime asOf;
  final List<ChargedRate> charged;
  final double taxTotal;
  final String currency;

  const TaxSnapshot({
    required this.status,
    required this.asOf,
    required this.charged,
    required this.taxTotal,
    this.currency = 'USD',
    this.reason,
    this.destinationState,
    this.referenceRate,
    this.referenceJurisdiction,
    this.referenceSource,
    this.referenceEffectiveFrom,
  });

  TaxSnapshot.fromRow(Map<String, dynamic> r)
      : status = _status(r['status'] as String?),
        reason = r['reason'] as String?,
        destinationState = r['destination_state'] as String?,
        referenceRate = (r['reference_rate'] as num?)?.toDouble(),
        referenceJurisdiction = r['reference_jurisdiction'] as String?,
        referenceSource = r['reference_source'] as String?,
        referenceEffectiveFrom = _day(r['reference_effective_from']),
        asOf = _day(r['as_of_date']) ?? DateTime.now(),
        charged = [
          for (final c in (r['charged'] as List? ?? const []))
            ChargedRate(
              ((c as Map)['rate'] as num).toDouble(),
              (c['taxable_amount'] as num).toDouble(),
              (c['tax_amount'] as num).toDouble(),
            ),
        ],
        taxTotal = (r['tax_total'] as num?)?.toDouble() ?? 0,
        currency = (r['currency'] as String?) ?? 'USD';

  static DateTime? _day(Object? v) => v == null ? null : DateTime.tryParse('$v');

  static TaxSnapshotStatus _status(String? s) => switch (s) {
        'matches_reference' => TaxSnapshotStatus.matchesReference,
        'manual_override' => TaxSnapshotStatus.manualOverride,
        'no_tax' => TaxSnapshotStatus.noTax,
        // Anything unknown is treated as needing a person to look.
        _ => TaxSnapshotStatus.requiresReview,
      };

  /// True when the invoice's tax no longer equals what was recorded at issue
  /// (its lines were edited afterwards) -- worth telling the accountant.
  bool changedSinceIssue(double currentTaxTotal) =>
      (currentTaxTotal - taxTotal).abs() >= 0.005;

  /// "6%" or "6.25%" -- what was charged, one entry per distinct rate.
  String get chargedLabel => charged.isEmpty
      ? 'none'
      : charged.map((c) => _pct(c.rate)).join(' and ');

  String get headline => switch (status) {
        TaxSnapshotStatus.matchesReference => 'Sales tax matches the reference rate',
        TaxSnapshotStatus.manualOverride => 'Sales tax differs from the reference rate',
        TaxSnapshotStatus.requiresReview => 'Sales tax needs review',
        TaxSnapshotStatus.noTax => 'No sales tax charged',
      };

  /// The facts under the headline, in words.
  String get detail {
    final ref = referenceRate;
    final where = referenceJurisdiction ?? destinationState;
    switch (status) {
      case TaxSnapshotStatus.matchesReference:
        return 'Charged $chargedLabel. Reference: ${_pct(ref ?? 0)} '
            '${where == null ? '' : '($where) '}on ${formatDocDate(asOf)}'
            '${referenceSource == null ? '' : ' · $referenceSource'}.';
      case TaxSnapshotStatus.manualOverride:
        return 'Charged $chargedLabel; the reference for '
            '${destinationState ?? 'the billing address'} is ${_pct(ref ?? 0)}. '
            'Fine for a deliberate exemption or rate; check it was intended.';
      case TaxSnapshotStatus.requiresReview:
        return '${reason ?? 'The tax could not be checked.'} Charged $chargedLabel.';
      case TaxSnapshotStatus.noTax:
        return (ref != null && ref > 0)
            ? 'The reference rate for ${destinationState ?? 'the billing address'} '
                'is ${_pct(ref)}, so check none is owed.'
            : 'Nothing was taxed on this invoice.';
    }
  }

  static String _pct(double v) => formatPercent(v).isEmpty ? '0%' : formatPercent(v);
}

class TaxSnapshotService {
  final _db = Supabase.instance.client;

  /// Null when there is no snapshot: a draft, an invoice issued before this
  /// existed, or a portal client (only the firm's members can read it).
  Future<TaxSnapshot?> forInvoice(String invoiceId) async {
    final row = await _db
        .from('invoice_tax_snapshots')
        .select('status, reason, destination_state, reference_rate, '
            'reference_jurisdiction, reference_source, reference_effective_from, '
            'as_of_date, charged, tax_total, currency')
        .eq('invoice_id', invoiceId)
        .maybeSingle();
    return row == null
        ? null
        : TaxSnapshot.fromRow(Map<String, dynamic>.from(row));
  }
}
