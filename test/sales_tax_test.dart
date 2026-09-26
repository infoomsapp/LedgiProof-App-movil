// Sales tax on an invoice is filled from the client's state; a wrong or missed
// match means a client is charged the wrong tax or has to type it by hand.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/sales_tax_service.dart';

Map<String, dynamic> row({
  double rate = 6,
  String name = 'Maryland',
  String from = '2026-01-01',
  String? to,
  String? zip,
  String category = 'general',
}) =>
    {
      'rate': rate,
      'jurisdiction_name': name,
      'effective_from': from,
      'effective_to': to,
      'postal_code': zip,
      'category': category,
    };

void main() {
  group('normalizeStateCode', () {
    test('finds the state however it was typed', () {
      expect(normalizeStateCode('mD'), 'MD'); // the real value on a client
      expect(normalizeStateCode(' md '), 'MD');
      expect(normalizeStateCode('Maryland'), 'MD');
      expect(normalizeStateCode('new york'), 'NY');
      expect(normalizeStateCode('District of Columbia'), 'DC');
    });
    test('rejects what is not a state', () {
      expect(normalizeStateCode(null), isNull);
      expect(normalizeStateCode(''), isNull);
      expect(normalizeStateCode('ZZ'), isNull);
      expect(normalizeStateCode('Ontario'), isNull);
    });
  });

  group('pickSalesTaxRate', () {
    final day = DateTime(2026, 9, 26);

    test('a state-wide rate', () {
      final r = pickSalesTaxRate([row()], stateCode: 'MD', date: day);
      expect(r!.ratePct, 6);
      expect(r.jurisdiction, 'Maryland');
      expect(r.stateCode, 'MD');
    });

    test('nothing on file, or not yet in force, gives null', () {
      expect(pickSalesTaxRate([], stateCode: 'MD', date: day), isNull);
      expect(pickSalesTaxRate([row(from: '2027-01-01')], stateCode: 'MD', date: day), isNull);
    });

    test('an ended rate is ignored, the current one wins', () {
      final r = pickSalesTaxRate([
        row(rate: 5, from: '2020-01-01', to: '2025-12-31'),
        row(rate: 6, from: '2026-01-01'),
      ], stateCode: 'MD', date: day);
      expect(r!.ratePct, 6);
    });

    test('the newest start date wins among current rates', () {
      final r = pickSalesTaxRate([
        row(rate: 5, from: '2024-01-01'),
        row(rate: 6, from: '2026-01-01'),
      ], stateCode: 'MD', date: day);
      expect(r!.ratePct, 6);
    });

    test('a ZIP-specific rate beats the state-wide one, only for that ZIP', () {
      final rows = [row(rate: 6), row(rate: 7.5, name: 'Baltimore', zip: '21201')];
      expect(pickSalesTaxRate(rows, stateCode: 'MD', postal: '21201', date: day)!.ratePct, 7.5);
      expect(pickSalesTaxRate(rows, stateCode: 'MD', postal: '24563', date: day)!.ratePct, 6);
      expect(pickSalesTaxRate(rows, stateCode: 'MD', date: day)!.ratePct, 6);
    });

    test('the wanted category beats general; other categories are ignored', () {
      final rows = [row(rate: 6), row(rate: 0, category: 'services'), row(rate: 9, category: 'alcohol')];
      expect(pickSalesTaxRate(rows, stateCode: 'MD', category: 'services', date: day)!.ratePct, 0);
      expect(pickSalesTaxRate(rows, stateCode: 'MD', date: day)!.ratePct, 6);
    });
  });
}
