// Invoice line math in integer cents, the same steps and rounding as the
// database trigger public.compute_invoice_item_lines (and the web's
// src/lib/money.ts), so the total shown while composing is what gets saved:
//
//   line_subtotal := ROUND(quantity * unit_price, 2)
//   line_discount := ROUND(line_subtotal * discount_pct / 100, 2)
//   line_tax      := ROUND((line_subtotal - line_discount) * tax_rate / 100, 2)
//   line_total    := line_subtotal - line_discount + line_tax
//
// Exact decimals (BigInt), rounded half away from zero like Postgres NUMERIC.
// quantity and unit_price are rounded to their column scales (4 and 2) first,
// as the database does on insert.

class _Dec {
  final BigInt units;
  final int scale;
  const _Dec(this.units, this.scale);
}

final _ten = BigInt.from(10);
BigInt _pow10(int n) => _ten.pow(n);

/// The decimal the user typed: 1.005.toString() is "1.005", not 1.00499...
_Dec _dec(double n) {
  if (!n.isFinite) return _Dec(BigInt.zero, 0);
  var s = n.toString();
  if (s.contains('e') || s.contains('E')) {
    s = n.toStringAsFixed(20).replaceFirst(RegExp(r'\.?0+$'), '');
  }
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  final frac = parts.length > 1 ? parts[1] : '';
  final units = BigInt.parse(parts[0] + frac);
  return _Dec(neg ? -units : units, frac.length);
}

/// a / b rounded half away from zero. b > 0.
BigInt _divRound(BigInt a, BigInt b) {
  final q = a ~/ b;
  final r = a.remainder(b);
  if (r.abs() * BigInt.two >= b) return q + (a.isNegative ? -BigInt.one : BigInt.one);
  return q;
}

BigInt _atScale(_Dec d, int scale) => d.scale <= scale
    ? d.units * _pow10(scale - d.scale)
    : _divRound(d.units, _pow10(d.scale - scale));

int toCents(double dollars) => _atScale(_dec(dollars), 2).toInt();

/// One line's total in cents.
int lineTotalCents({
  required double quantity,
  required double unitPrice,
  double discountPct = 0,
  double taxRate = 0,
}) {
  final qty = _atScale(_dec(quantity), 4);
  final price = _atScale(_dec(unitPrice), 2);
  final disc = _dec(discountPct);
  final rate = _dec(taxRate);
  final subtotal = _divRound(qty * price, _pow10(4));
  final discount = _divRound(subtotal * disc.units, BigInt.from(100) * _pow10(disc.scale));
  final tax = _divRound((subtotal - discount) * rate.units, BigInt.from(100) * _pow10(rate.scale));
  return (subtotal - discount + tax).toInt();
}
