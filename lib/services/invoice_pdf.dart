import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/doc_format.dart';
import '../utils/invoice_status.dart';

/// Everything the printed invoice needs, already shaped for printing. Built from
/// the same rows the app reads (invoices, invoice_items, invoice_payments) plus
/// the firm's branding, so the PDF cannot drift from what the screen shows.
class PdfLine {
  final String description;
  final double quantity;
  final double unitPrice;
  final double discountPct;
  final double taxRate;
  final double lineTotal;
  const PdfLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.discountPct,
    required this.taxRate,
    required this.lineTotal,
  });
}

class PdfPaymentLine {
  final DateTime date;
  final String method;
  final String? reference;
  final double amount;
  const PdfPaymentLine({
    required this.date,
    required this.method,
    required this.reference,
    required this.amount,
  });
}

class InvoicePdfInput {
  final String number;
  final String status;
  final String currency;
  final String? title;
  final DateTime? issueDate;
  final DateTime? dueDate;

  final String orgName;
  final String? brandHex;
  final String? footer;
  final String? terms;
  final String? paymentInstructions;
  final String? notes;

  final List<String> billToLines; // name, company, address, email...
  final List<PdfLine> lines;
  final List<PdfPaymentLine> payments;

  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double amountPaid;
  final double balanceDue;

  /// The public page where the client can pay; printed with a QR code. Null for
  /// a draft, a paid or a void invoice.
  final String? payUrl;

  const InvoicePdfInput({
    required this.number,
    required this.status,
    required this.currency,
    required this.title,
    required this.issueDate,
    required this.dueDate,
    required this.orgName,
    required this.brandHex,
    required this.footer,
    required this.terms,
    required this.paymentInstructions,
    required this.notes,
    required this.billToLines,
    required this.lines,
    required this.payments,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.amountPaid,
    required this.balanceDue,
    required this.payUrl,
  });

  bool get hasDiscount => lines.any((l) => l.discountPct > 0);
  bool get hasTax => lines.any((l) => l.taxRate > 0);
}

const _defaultBrand = 0x2563EB;
const _ink = PdfColor.fromInt(0xFF111827);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _rule = PdfColor.fromInt(0xFFE5E7EB);
const _green = PdfColor.fromInt(0xFF16A34A);
const _red = PdfColor.fromInt(0xFFDC2626);

pw.Text _t(
  String s, {
  double size = 10,
  bool bold = false,
  PdfColor color = _ink,
  pw.TextAlign? align,
}) =>
    pw.Text(
      toPdfText(s),
      textAlign: align,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    );

/// Renders the invoice to PDF bytes (US Letter). Uses only widgets that can
/// break across pages (a table, text, plain rows), so a long invoice becomes
/// several pages instead of failing with "too many pages".
///
/// [compress] is on for real use; tests turn it off to read the text back.
Future<Uint8List> buildInvoicePdf(
  InvoicePdfInput d, {
  Uint8List? logo,
  bool compress = true,
}) async {
  final brand = PdfColor.fromInt(0xFF000000 | (parseHexColor(d.brandHex) ?? _defaultBrand));
  final doc = pw.Document(
    title: 'Invoice ${d.number}',
    author: toPdfText(d.orgName),
    compress: compress,
  );

  pw.MemoryImage? logoImage;
  if (logo != null) {
    try {
      logoImage = pw.MemoryImage(logo);
    } catch (_) {
      logoImage = null; // an unreadable image is simply left out
    }
  }

  final standing = invoiceStanding(
    status: d.status,
    total: d.total,
    balanceDue: d.balanceDue,
    dueDate: d.dueDate,
  );
  final badge = switch (standing.bucket) {
    InvoiceBucket.paid => ('PAID', _green),
    InvoiceBucket.voided => ('VOID', _muted),
    InvoiceBucket.overdue => ('OVERDUE', _red),
    InvoiceBucket.draft => ('DRAFT', _muted),
    InvoiceBucket.awaiting => null,
  };

  String money(double v) => formatMoney(v, currency: d.currency);

  // ── Header ────────────────────────────────────────────────────────────────
  final header = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null)
              pw.Container(
                height: 46,
                margin: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Image(logoImage, fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft),
              ),
            _t(d.orgName, size: 15, bold: true),
          ],
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _t('INVOICE', size: 24, bold: true, color: brand),
          pw.SizedBox(height: 2),
          _t('#${d.number}', size: 11, color: _muted),
          if (badge != null) ...[
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: badge.$2, width: 1),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: _t(badge.$1, size: 9, bold: true, color: badge.$2),
            ),
          ],
        ],
      ),
    ],
  );

  // ── Bill to + dates ───────────────────────────────────────────────────────
  final meta = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _t('BILL TO', size: 8, bold: true, color: _muted),
            pw.SizedBox(height: 4),
            if (d.billToLines.isEmpty)
              _t('-', color: _muted)
            else ...[
              _t(d.billToLines.first, size: 11, bold: true),
              for (final l in d.billToLines.skip(1)) _t(l, color: _muted),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (d.issueDate != null) _kv('Issued', formatDocDate(d.issueDate!)),
          if (d.dueDate != null) _kv('Due', formatDocDate(d.dueDate!)),
          _kv('Amount due', money(d.balanceDue), bold: true, color: brand),
        ],
      ),
    ],
  );

  // ── Line items ────────────────────────────────────────────────────────────
  final cols = <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(4.2),
    1: const pw.FlexColumnWidth(0.9),
    2: const pw.FlexColumnWidth(1.4),
  };
  var next = 3;
  final discCol = d.hasDiscount ? next++ : -1;
  final taxCol = d.hasTax ? next++ : -1;
  final amountCol = next;
  if (discCol >= 0) cols[discCol] = const pw.FlexColumnWidth(1);
  if (taxCol >= 0) cols[taxCol] = const pw.FlexColumnWidth(1);
  cols[amountCol] = const pw.FlexColumnWidth(1.5);

  pw.Widget cell(String s, {bool bold = false, PdfColor color = _ink, bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Align(
          alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          child: _t(s, size: 9.5, bold: bold, color: color, align: right ? pw.TextAlign.right : null),
        ),
      );

  pw.TableRow headRow() => pw.TableRow(
        repeat: true, // the header comes back on every page
        decoration: pw.BoxDecoration(color: brand),
        children: [
          cell('Description', bold: true, color: PdfColors.white),
          cell('Qty', bold: true, color: PdfColors.white, right: true),
          cell('Unit price', bold: true, color: PdfColors.white, right: true),
          if (discCol >= 0) cell('Disc.', bold: true, color: PdfColors.white, right: true),
          if (taxCol >= 0) cell('Tax', bold: true, color: PdfColors.white, right: true),
          cell('Amount', bold: true, color: PdfColors.white, right: true),
        ],
      );

  final table = pw.Table(
    columnWidths: cols,
    border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _rule, width: 0.7)),
    children: [
      headRow(),
      for (final l in d.lines)
        pw.TableRow(children: [
          cell(l.description),
          cell(formatQuantity(l.quantity), right: true),
          cell(money(l.unitPrice), right: true),
          if (discCol >= 0) cell(formatPercent(l.discountPct), right: true),
          if (taxCol >= 0) cell(formatPercent(l.taxRate), right: true),
          cell(money(l.lineTotal), right: true),
        ]),
    ],
  );

  // ── Totals ────────────────────────────────────────────────────────────────
  pw.Widget totalRow(String label, String value,
          {bool bold = false, PdfColor color = _ink, bool rule = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: rule
            ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.8)))
            : null,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _t(label, size: bold ? 11 : 10, bold: bold, color: bold ? color : _muted),
            _t(value, size: bold ? 11 : 10, bold: bold, color: color),
          ],
        ),
      );

  final totals = pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 230,
      child: pw.Column(
        children: [
          totalRow('Subtotal', money(d.subtotal)),
          if (d.discountTotal > 0) totalRow('Discount', '-${money(d.discountTotal)}'),
          if (d.taxTotal > 0) totalRow('Tax', money(d.taxTotal)),
          totalRow('Total', money(d.total), bold: true, rule: true),
          if (d.amountPaid > 0) totalRow('Paid', '-${money(d.amountPaid)}', color: _green),
          if (d.amountPaid > 0)
            totalRow('Balance due', money(d.balanceDue), bold: true, color: brand, rule: true),
        ],
      ),
    ),
  );

  // ── Payments received ─────────────────────────────────────────────────────
  final payments = d.payments.isEmpty
      ? null
      : pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _t('PAYMENTS RECEIVED', size: 8, bold: true, color: _muted),
            pw.SizedBox(height: 4),
            for (final p in d.payments)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: _t(
                        '${formatDocDate(p.date)} - ${p.method}'
                        '${(p.reference ?? '').isEmpty ? '' : ' (Ref ${p.reference})'}',
                        size: 9,
                        color: _muted,
                      ),
                    ),
                    _t(money(p.amount), size: 9),
                  ],
                ),
              ),
          ],
        );

  // ── How to pay ────────────────────────────────────────────────────────────
  final instructions = (d.paymentInstructions ?? '').trim();
  final howToPay = (instructions.isEmpty && d.payUrl == null)
      ? null
      : pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _rule, width: 0.8),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _t('HOW TO PAY', size: 8, bold: true, color: _muted),
                    pw.SizedBox(height: 4),
                    if (d.payUrl != null) ...[
                      _t('Pay online, securely:', size: 9.5),
                      _t(d.payUrl!, size: 9, color: brand),
                      pw.SizedBox(height: 4),
                    ],
                    if (instructions.isNotEmpty) _t(instructions, size: 9.5),
                  ],
                ),
              ),
              if (d.payUrl != null) ...[
                pw.SizedBox(width: 12),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: d.payUrl!,
                  width: 74,
                  height: 74,
                  drawText: false,
                ),
              ],
            ],
          ),
        );

  pw.Widget block(String label, String text) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _t(label, size: 8, bold: true, color: _muted),
          pw.SizedBox(height: 3),
          _t(text, size: 9.5),
        ],
      );

  final notes = (d.notes ?? '').trim();
  final terms = (d.terms ?? '').trim();
  final footer = (d.footer ?? '').trim();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 44),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _t(footer.isEmpty ? d.orgName : footer, size: 8, color: _muted),
          _t('Invoice ${d.number}  -  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              size: 8, color: _muted),
        ],
      ),
      build: (ctx) => [
        header,
        pw.SizedBox(height: 22),
        meta,
        if ((d.title ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _t(d.title!.trim(), size: 11, bold: true),
        ],
        pw.SizedBox(height: 18),
        table,
        pw.SizedBox(height: 14),
        totals,
        if (payments != null) ...[pw.SizedBox(height: 16), payments],
        if (howToPay != null) ...[pw.SizedBox(height: 18), howToPay],
        if (notes.isNotEmpty) ...[pw.SizedBox(height: 16), block('NOTES', notes)],
        if (terms.isNotEmpty) ...[pw.SizedBox(height: 12), block('TERMS', terms)],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _kv(String k, String v, {bool bold = false, PdfColor color = _ink}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _t('$k  ', size: 9.5, color: _muted),
          _t(v, size: bold ? 12 : 10, bold: bold, color: color),
        ],
      ),
    );
