// Money and text on a printed invoice have to be exactly right.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/utils/doc_format.dart';

void main() {
  group('formatMoney', () {
    test('thousands separators and cents', () {
      expect(formatMoney(0), '\$0.00');
      expect(formatMoney(5), '\$5.00');
      expect(formatMoney(1234.5), '\$1,234.50');
      expect(formatMoney(1234567.891), '\$1,234,567.89');
      expect(formatMoney(999.999), '\$1,000.00'); // rounds, then separates
    });
    test('negative and other currencies', () {
      expect(formatMoney(-45.1), '-\$45.10');
      expect(formatMoney(-0.001), '\$0.00'); // never "-$0.00"
      expect(formatMoney(1500, currency: 'EUR'), 'EUR 1,500.00');
    });
  });

  test('dates print the calendar day they hold', () {
    expect(formatDocDate(DateTime(2026, 9, 25)), 'Sep 25, 2026');
    expect(formatDocDate(DateTime(2027, 1, 4)), 'Jan 4, 2027');
  });

  test('percent and quantity drop pointless zeros', () {
    expect(formatPercent(0), '');
    expect(formatPercent(8), '8%');
    expect(formatPercent(8.25), '8.25%');
    expect(formatPercent(7.5), '7.5%');
    expect(formatQuantity(2), '2');
    expect(formatQuantity(1.5), '1.5');
    expect(formatQuantity(0.25), '0.25');
  });

  test('address lines', () {
    expect(cityLine(city: 'Austin', state: 'TX', postalCode: '78701'), 'Austin, TX 78701');
    expect(cityLine(city: 'Austin'), 'Austin');
    expect(cityLine(state: 'TX', postalCode: '78701'), 'TX 78701');
    expect(cityLine(), '');
    expect(compactLines(['A', null, '  ', ' B ']), ['A', 'B']);
  });

  group('toPdfText keeps the PDF fonts from failing', () {
    test('Latin-1 passes through (Spanish names)', () {
      expect(toPdfText('Ñandú Peña — José'), 'Ñandú Peña - José');
    });
    test('typographic characters become plain ones', () {
      expect(toPdfText('“Quoted” ’s • item…'), '"Quoted" \'s - item...');
    });
    test('anything else becomes a question mark, newlines survive', () {
      expect(toPdfText('a\nb 中文 \u{1F600}'), 'a\nb ?? ?');
    });
  });

  test('brand colours', () {
    expect(parseHexColor('#3b82f6'), 0x3b82f6);
    expect(parseHexColor('FF0000'), 0xFF0000);
    expect(parseHexColor('#f00'), 0xFF0000);
    expect(parseHexColor('red'), isNull);
    expect(parseHexColor(null), isNull);
    expect(parseHexColor('#12345'), isNull);
  });
}
