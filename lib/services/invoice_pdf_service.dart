import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/doc_format.dart';
import 'invoice_pdf.dart';
import 'invoice_service.dart';

/// Turns an invoice the app already loaded, plus the few rows the screen does
/// not read (the full invoice row, the firm's branding, the client), into the
/// printable [InvoicePdfInput]. Pure -- no network -- so it is tested on its own.
///
/// Money is never recomputed here: subtotal, discount, tax, total, paid and
/// balance are the stored values, so the PDF prints the same numbers the screen
/// and the client's payment page show.
InvoicePdfInput assembleInvoicePdfInput(
  InvoiceDetail d, {
  required Map<String, dynamic> invoiceRow,
  Map<String, dynamic>? org,
  Map<String, dynamic>? client,
}) {
  String? s(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v == null) return null;
    final t = '$v'.trim();
    return t.isEmpty ? null : t;
  }

  // The bill-to is what the invoice froze when it was issued; a live client
  // row is only the fallback for an invoice that has no snapshot.
  final frozen = s(invoiceRow, 'bill_to_snapshot_at') != null ||
      s(invoiceRow, 'bill_to_name') != null;
  final src = frozen ? invoiceRow : client;
  final p = frozen ? 'bill_to_' : '';
  final name = frozen ? s(src, 'bill_to_name') : (s(src, 'display_name') ?? d.clientName);
  final company = s(src, frozen ? 'bill_to_company' : 'company_name');
  final taxId = frozen ? s(src, 'bill_to_tax_id') : null;
  final billTo = compactLines([
    name ?? d.clientName,
    company != null && company != name ? company : null,
    s(src, '${p}address_line1'),
    s(src, '${p}address_line2'),
    cityLine(
      city: s(src, '${p}city'),
      state: s(src, '${p}state'),
      postalCode: s(src, '${p}postal_code'),
    ),
    frozen ? s(src, 'bill_to_country') : null,
    s(src, frozen ? 'bill_to_email' : 'email'),
    s(src, frozen ? 'bill_to_phone' : 'phone'),
    taxId == null ? null : 'Tax ID $taxId',
  ]);

  final open = !d.isPaid && !d.isVoid && !d.isDraft;
  return InvoicePdfInput(
    number: d.invoiceNumber,
    status: d.status,
    currency: d.currency,
    title: s(invoiceRow, 'title'),
    issueDate: d.issueDate,
    dueDate: d.dueDate,
    orgName: s(org, 'name') ?? 'Invoice',
    brandHex: s(org, 'brand_color'),
    footer: s(invoiceRow, 'footer') ?? s(org, 'invoice_footer'),
    terms: s(invoiceRow, 'terms') ?? s(org, 'invoice_terms'),
    // How to pay is only useful while something is owed.
    paymentInstructions: open ? s(org, 'payment_instructions') : null,
    notes: d.notes,
    billToLines: billTo,
    lines: [
      for (final i in d.items)
        PdfLine(
          description: i.description,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          discountPct: i.discountPct,
          taxRate: i.taxRate,
          lineTotal: i.lineTotal,
        ),
    ],
    payments: [
      for (final pay in d.payments)
        PdfPaymentLine(
          date: pay.date,
          method: paymentMethods[pay.method] ?? (pay.method ?? 'Payment'),
          reference: pay.reference,
          amount: pay.amount,
        ),
    ],
    subtotal: d.subtotal,
    discountTotal: d.discountTotal,
    taxTotal: d.taxTotal,
    total: d.total,
    amountPaid: d.amountPaid,
    balanceDue: d.balanceDue,
    payUrl: d.canPayOnline ? InvoiceService.publicUrl(d.publicToken!) : null,
  );
}

/// File name safe on every phone: "Invoice-INV-0042.pdf".
String invoicePdfFileName(String number) {
  final safe = number.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return 'Invoice-${safe.isEmpty ? 'document' : safe}.pdf';
}

/// Loads what the PDF needs and builds it. Works for the firm and for the
/// firm's client: the invoice row and its client are readable by both under
/// RLS; branding comes from the organization row when it is readable and from
/// the public-invoice function (which exposes only branding) when it is not.
class InvoicePdfService {
  final _db = Supabase.instance.client;

  Future<Uint8List> build(InvoiceDetail d) async {
    final row = await _db
        .from('invoices')
        .select('title, footer, terms, org_id, bill_to_name, bill_to_company, '
            'bill_to_email, bill_to_phone, bill_to_tax_id, bill_to_address_line1, '
            'bill_to_address_line2, bill_to_city, bill_to_state, '
            'bill_to_postal_code, bill_to_country, bill_to_snapshot_at')
        .eq('id', d.id)
        .single();
    final invoiceRow = Map<String, dynamic>.from(row);

    Map<String, dynamic>? org;
    try {
      final o = await _db
          .from('organizations')
          .select('name, logo_url, brand_color, invoice_footer, invoice_terms, '
              'payment_instructions')
          .eq('id', invoiceRow['org_id'] as String)
          .maybeSingle();
      if (o != null) org = Map<String, dynamic>.from(o);
    } catch (_) {}
    if (org == null && d.publicToken != null && !d.isDraft) {
      try {
        final r = await _db.rpc('get_invoice_by_public_token', params: {
          'p_token': d.publicToken,
          'p_track_view': false, // printing must not count as the client opening it
        });
        final o = (r as Map)['org'];
        if (o is Map) org = Map<String, dynamic>.from(o);
      } catch (_) {}
    }

    Map<String, dynamic>? client;
    if (invoiceRow['bill_to_snapshot_at'] == null && invoiceRow['bill_to_name'] == null) {
      try {
        final c = await _db
            .from('clients')
            .select('display_name, company_name, email, phone, address_line1, '
                'address_line2, city, state, postal_code')
            .eq('id', d.clientId)
            .maybeSingle();
        if (c != null) client = Map<String, dynamic>.from(c);
      } catch (_) {}
    }

    final input = assembleInvoicePdfInput(d,
        invoiceRow: invoiceRow, org: org, client: client);
    final logo = await _fetchLogo(org?['logo_url'] as String?);
    return buildInvoicePdf(input, logo: logo);
  }

  /// The firm's logo, or null. Best effort by design: a slow or missing logo
  /// must never stop an invoice from being produced.
  Future<Uint8List?> _fetchLogo(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      const maxBytes = 3 * 1024 * 1024;
      final out = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 10))) {
        out.add(chunk);
        if (out.length > maxBytes) return null;
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
