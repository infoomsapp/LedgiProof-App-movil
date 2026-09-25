/// Formatting shared by printed documents (the invoice PDF): money with
/// thousands separators, dates, address lines, and text made safe for the PDF's
/// built-in fonts. No Flutter and no `intl` -- so it can be tested on its own
/// and behaves the same everywhere.
library;

/// "$1,234.56", "-$5.00", "EUR 1,234.56". Rounds to cents.
String formatMoney(double value, {String currency = 'USD'}) {
  final cents = (value.abs() * 100).round();
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final sign = value < 0 && cents != 0 ? '-' : '';
  final symbol = currency == 'USD' ? '\$' : '$currency ';
  return '$sign$symbol$buf.$frac';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Sep 25, 2026". A date-only value is printed as that calendar day whatever
/// the phone's time zone (no shifting a "2026-09-25" to the 24th).
String formatDocDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Percent for a table cell: 0 -> "", 8 -> "8%", 8.25 -> "8.25%".
String formatPercent(double v) {
  if (v == 0) return '';
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return '$s%';
}

/// Quantity: 2 -> "2", 1.5 -> "1.5", 0.25 -> "0.25".
String formatQuantity(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// City/state/zip on one line: "Austin, TX 78701".
String cityLine({String? city, String? state, String? postalCode}) {
  final c = (city ?? '').trim();
  final s = (state ?? '').trim();
  final z = (postalCode ?? '').trim();
  final region = [s, z].where((p) => p.isNotEmpty).join(' ');
  return [c, region].where((p) => p.isNotEmpty).join(', ');
}

/// Non-empty, trimmed lines only, in order.
List<String> compactLines(Iterable<String?> parts) =>
    [for (final p in parts) if ((p ?? '').trim().isNotEmpty) p!.trim()];

/// The PDF's built-in fonts cover Latin-1 (accents, ñ, ç...), not the rest of
/// Unicode. Common typographic characters are mapped to plain equivalents and
/// anything else outside that range becomes "?", so a stray emoji or a name in
/// another script can never make document generation fail or print blanks.
String toPdfText(String s) {
  const map = {
    '–': '-', '—': '-', '−': '-',
    '‘': "'", '’': "'", '“': '"', '”': '"',
    '•': '-', '…': '...', ' ': ' ',
  };
  final out = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    if (map.containsKey(ch)) {
      out.write(map[ch]);
    } else if (rune == 0x0A || rune == 0x0D || rune == 0x09 || (rune >= 0x20 && rune <= 0xFF)) {
      out.write(ch);
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

/// "#RRGGBB" (or "RRGGBB", or "#RGB") to a 0xRRGGBB int; null when it is not a
/// colour. Used for the brand colour, which is free text in the database.
int? parseHexColor(String? hex) {
  var h = (hex ?? '').trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return int.parse(h, radix: 16);
}
