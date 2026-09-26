// The tax snapshot is the record an accountant relies on when a rate is
// questioned, so what it says must match what the database stored.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/tax_snapshot_service.dart';

Map<String, dynamic> row({
  String status = 'matches_reference',
  String? reason,
  List<Map<String, dynamic>>? charged,
  num? ref = 6,
  double tax = 60,
}) =>
    {
      'status': status,
      'reason': reason,
      'destination_state': 'MD',
      'reference_rate': ref,
      'reference_jurisdiction': 'Maryland (state rate)',
      'reference_source': 'tax_foundation_2026',
      'reference_effective_from': '2026-01-01',
      'as_of_date': '2026-09-26',
      'charged': charged ?? [{'rate': 6, 'taxable_amount': 1000, 'tax_amount': 60}],
      'tax_total': tax,
      'currency': 'USD',
    };

void main() {
  test('reads what the database stores', () {
    final s = TaxSnapshot.fromRow(row());
    expect(s.status, TaxSnapshotStatus.matchesReference);
    expect(s.referenceRate, 6);
    expect(s.charged.single.taxAmount, 60);
    expect(s.chargedLabel, '6%');
    expect(s.destinationState, 'MD');
  });

  test('matching wording states the rate, place, date and source', () {
    final s = TaxSnapshot.fromRow(row());
    expect(s.headline, 'Sales tax matches the reference rate');
    expect(s.detail,
        'Charged 6%. Reference: 6% (Maryland (state rate)) on Sep 26, 2026 · tax_foundation_2026.');
  });

  test('a different rate says both numbers', () {
    final s = TaxSnapshot.fromRow(row(
        status: 'manual_override',
        charged: [{'rate': 7, 'taxable_amount': 100, 'tax_amount': 7}]));
    expect(s.headline, 'Sales tax differs from the reference rate');
    expect(s.detail, contains('Charged 7%'));
    expect(s.detail, contains('MD is 6%'));
  });

  test('needs review carries the reason', () {
    final s = TaxSnapshot.fromRow(row(
        status: 'requires_review',
        reason: 'The billing address has no state, so the tax could not be checked',
        ref: null));
    expect(s.headline, 'Sales tax needs review');
    expect(s.detail, contains('has no state'));
  });

  test('no tax: nudges only when the state has a rate', () {
    expect(TaxSnapshot.fromRow(row(status: 'no_tax', charged: [], tax: 0)).detail,
        contains('check none is owed'));
    expect(TaxSnapshot.fromRow(row(status: 'no_tax', charged: [], tax: 0, ref: 0)).detail,
        'Nothing was taxed on this invoice.');
    expect(TaxSnapshot.fromRow(row(status: 'no_tax', charged: [], tax: 0, ref: null)).detail,
        'Nothing was taxed on this invoice.');
  });

  test('several rates are all listed', () {
    final s = TaxSnapshot.fromRow(row(charged: [
      {'rate': 6, 'taxable_amount': 100, 'tax_amount': 6},
      {'rate': 8.25, 'taxable_amount': 100, 'tax_amount': 8.25},
    ]));
    expect(s.chargedLabel, '6% and 8.25%');
  });

  test('an unknown status is treated as needing review, not as fine', () {
    expect(TaxSnapshot.fromRow(row(status: 'something_new')).status,
        TaxSnapshotStatus.requiresReview);
  });

  test('spots tax edited after issue', () {
    final s = TaxSnapshot.fromRow(row(tax: 60));
    expect(s.changedSinceIssue(60), isFalse);
    expect(s.changedSinceIssue(60.004), isFalse);
    expect(s.changedSinceIssue(70), isTrue);
    expect(s.changedSinceIssue(0), isTrue);
  });
}
