// The invoice PDF is a document a client pays from and an accountant files, so
// what is printed has to be the numbers on the screen, it has to survive odd
// input, and it must paginate instead of failing.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/invoice_pdf.dart';

InvoicePdfInput input({
  List<PdfLine>? lines,
  List<PdfPaymentLine> payments = const [],
  String status = 'sent',
  double total = 1200,
  double paid = 0,
  String? payUrl = 'https://app.ledgiproof.com/i/tok123',
  String orgName = 'Acme Bookkeeping LLC',
  List<String> billTo = const ['Ana Perez', 'Perez Design LLC', 'ana@example.com'],
  String? instructions = 'Zelle to pay@acme.example',
  String? notes,
  String? brand = '#0F766E',
}) {
  final ls = lines ??
      const [
        PdfLine(description: 'Monthly bookkeeping', quantity: 1, unitPrice: 1000, discountPct: 0, taxRate: 0, lineTotal: 1000),
        PdfLine(description: 'Payroll processing', quantity: 2, unitPrice: 100, discountPct: 0, taxRate: 0, lineTotal: 200),
      ];
  return InvoicePdfInput(
    number: 'INV-0042',
    status: status,
    currency: 'USD',
    title: null,
    issueDate: DateTime(2026, 9, 1),
    dueDate: DateTime(2026, 10, 1),
    orgName: orgName,
    brandHex: brand,
    footer: 'Thank you for your business',
    terms: 'Net 30',
    paymentInstructions: instructions,
    notes: notes,
    billToLines: billTo,
    lines: ls,
    payments: payments,
    subtotal: total,
    discountTotal: 0,
    taxTotal: 0,
    total: total,
    amountPaid: paid,
    balanceDue: total - paid,
    payUrl: payUrl,
  );
}

String text(Uint8List pdf) => latin1.decode(pdf);

// The PDF writes every word as its own text run, "[(Net)]TJ ... [(30)]TJ", so
// the printed text is read back by joining the runs with spaces.
String printed(Uint8List pdf) =>
    RegExp(r'\[\((.*?)\)\]TJ').allMatches(text(pdf)).map((m) => m.group(1)!).join(' ');

int pageCount(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(text(pdf)).length;

void main() {
  test('produces a real PDF', () async {
    final bytes = await buildInvoicePdf(input());
    expect(text(bytes).startsWith('%PDF-'), isTrue);
    expect(text(bytes).trimRight().endsWith('%%EOF'), isTrue);
    expect(bytes.length, greaterThan(1500));
    expect(pageCount(bytes), 1);
  });

  test('prints the numbers the client is asked to pay', () async {
    final t = printed(await buildInvoicePdf(input(), compress: false));
    for (final expected in [
      'INV-0042',
      'Acme Bookkeeping LLC',
      'Ana Perez',
      'Monthly bookkeeping',
      '\$1,000.00',
      '\$1,200.00', // total / amount due
      'Sep 1, 2026',
      'Oct 1, 2026',
      'Zelle to pay@acme.example',
      'https://app.ledgiproof.com/i/tok123',
      'Net 30',
    ]) {
      expect(t, contains(expected), reason: 'missing "$expected"');
    }
  });

  test('a partly paid invoice shows paid and the remaining balance', () async {
    final t = printed(await buildInvoicePdf(
      input(
        paid: 500,
        payments: [PdfPaymentLine(date: DateTime(2026, 9, 10), method: 'Check', reference: '1042', amount: 500)],
      ),
      compress: false,
    ));
    expect(t, contains('Balance due'));
    expect(t, contains('\$700.00'));
    expect(t, contains('Ref 1042'));
    expect(t, contains('PAYMENTS RECEIVED'));
  });

  test('status stamps', () async {
    Future<String> stamp(String s, {double paid = 0}) async =>
        printed(await buildInvoicePdf(input(status: s, paid: paid), compress: false));
    expect(await stamp('paid', paid: 1200), contains('PAID'));
    expect(await stamp('void'), contains('VOID'));
    expect(await stamp('draft', paid: 0), contains('DRAFT'));
  });

  test('discount and tax columns only appear when a line uses them', () async {
    final plain = printed(await buildInvoicePdf(input(), compress: false));
    expect(plain, isNot(contains('Disc.')));
    final rich = printed(await buildInvoicePdf(
      input(lines: const [
        PdfLine(description: 'Consulting', quantity: 2, unitPrice: 100, discountPct: 10, taxRate: 8.25, lineTotal: 194.85),
      ]),
      compress: false,
    ));
    expect(rich, contains('Disc.'));
    expect(rich, contains('Tax'));
    expect(rich, contains('10%'));
    expect(rich, contains('8.25%'));
  });

  test('a very long invoice paginates instead of failing', () async {
    final many = [
      for (var i = 1; i <= 160; i++)
        PdfLine(description: 'Service line $i with a reasonably long description to wrap', quantity: 1, unitPrice: 10, discountPct: 0, taxRate: 0, lineTotal: 10),
    ];
    final bytes = await buildInvoicePdf(input(lines: many, total: 1600, notes: 'Note ' * 400));
    expect(pageCount(bytes), greaterThan(2));
    expect(text(bytes).trimRight().endsWith('%%EOF'), isTrue);
  });

  test('odd characters and a broken logo never break generation', () async {
    final bytes = await buildInvoicePdf(
      input(
        orgName: 'Ñandú “Peña” — 中文 LLC \u{1F600}',
        billTo: const ['José Ñ.', 'Calle 5 #12'],
        notes: 'Línea 1\nLínea 2 — gracias',
      ),
      logo: Uint8List.fromList([1, 2, 3, 4, 5]), // not an image
    );
    expect(text(bytes).startsWith('%PDF-'), isTrue);
  });

  test('no pay link and no instructions -> no how-to-pay box', () async {
    final t = printed(await buildInvoicePdf(input(payUrl: null, instructions: null), compress: false));
    expect(t, isNot(contains('HOW TO PAY')));
  });

  test('a missing brand colour or address still produces a document', () async {
    final bytes = await buildInvoicePdf(input(brand: 'not-a-colour', billTo: const []));
    expect(text(bytes).startsWith('%PDF-'), isTrue);
  });
}
