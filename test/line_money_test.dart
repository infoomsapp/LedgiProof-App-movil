// The compose screen's total must be what the database saves, to the cent.
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/line_money.dart';
import 'package:ledgiproof/services/invoice_service.dart';

void main() {
  test(r'rounds $1.005 like Postgres', () {
    expect(toCents(1.005), 101);
    expect(lineTotalCents(quantity: 1, unitPrice: 1.005), 101);
    expect(toCents(-1.005), -101);
  });

  test('the discount comes from the rounded subtotal', () {
    // 0.5 x 2.01 = 1.005 -> 1.01; 50% = 0.505 -> 0.51; total 0.50
    expect(lineTotalCents(quantity: 0.5, unitPrice: 2.01, discountPct: 50), 50);
  });

  test('the total is the sum of the rounded parts', () {
    // 5c, discount 1c, tax ROUND(0.4c) = 0 -> 4c (the old float formula said 4.95c -> 5c)
    expect(lineTotalCents(quantity: 1, unitPrice: 0.05, discountPct: 10, taxRate: 10), 4);
  });

  test('three-decimal tax rates', () {
    expect(lineTotalCents(quantity: 2.5, unitPrice: 80, taxRate: 8.875), 21775);
  });

  test('a draft line uses the same math', () {
    final d = DraftItem(quantity: 3, unitPrice: 100, discountPct: 10, taxRate: 8.5);
    expect(d.lineTotalCents, 29295);
    expect(d.lineTotal, 292.95);
  });
}
