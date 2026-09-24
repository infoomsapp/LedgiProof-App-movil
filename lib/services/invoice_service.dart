import 'package:supabase_flutter/supabase_flutter.dart';

/// One invoice with its line items, plus the online-payment path.
///
/// Mirrors the web's ClientInvoices/PortalInvoices pages and
/// stripe.service.ts's createInvoiceCheckoutSession: same edge function, same
/// body shape, same `type: 'invoice'` discriminator.
class InvoiceItem {
  final String description;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  InvoiceItem.fromRow(Map<String, dynamic> r)
      : description = (r['description'] as String?) ?? '',
        quantity = (r['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal = (r['line_total'] as num?)?.toDouble() ??
            ((r['quantity'] as num?)?.toDouble() ?? 0) *
                ((r['unit_price'] as num?)?.toDouble() ?? 0);
}

class InvoiceDetail {
  final String id;
  final String invoiceNumber;
  final String status;
  final double total;
  final double balanceDue;
  final String currency;
  final DateTime? dueDate;
  final DateTime? issueDate;
  final String? notes;
  final String? publicToken;
  final List<InvoiceItem> items;

  InvoiceDetail({
    required this.id,
    required this.invoiceNumber,
    required this.status,
    required this.total,
    required this.balanceDue,
    required this.currency,
    required this.dueDate,
    required this.issueDate,
    required this.notes,
    required this.publicToken,
    required this.items,
  });

  bool get isPaid => status == 'paid' || balanceDue <= 0;
  bool get isDraft => status == 'draft';

  /// Payment needs a public token, which is minted when an accountant marks
  /// the invoice sent. A portal client cannot mint one themselves: the
  /// invoices UPDATE policy requires owner/admin/accountant on the org, and a
  /// portal client holds no org role at all. So this is a real state to
  /// handle, not an edge case to paper over with a write that RLS rejects.
  bool get canPayOnline => !isPaid && !isDraft && publicToken != null;
}

class InvoiceService {
  final _db = Supabase.instance.client;

  Future<InvoiceDetail> getDetail(String invoiceId) async {
    final inv = await _db
        .from('invoices')
        .select('id, invoice_number, status, total, balance_due, currency, '
            'due_date, issue_date, notes, public_token')
        .eq('id', invoiceId)
        .single();

    final items = await _db
        .from('invoice_items')
        .select('description, quantity, unit_price, line_total')
        .eq('invoice_id', invoiceId);

    final total = (inv['total'] as num?)?.toDouble() ?? 0;
    return InvoiceDetail(
      id: inv['id'] as String,
      invoiceNumber: (inv['invoice_number'] as String?) ?? '—',
      status: (inv['status'] as String?) ?? 'draft',
      total: total,
      balanceDue: (inv['balance_due'] as num?)?.toDouble() ?? total,
      currency: (inv['currency'] as String?) ?? 'USD',
      dueDate: inv['due_date'] == null
          ? null
          : DateTime.tryParse(inv['due_date'] as String),
      issueDate: inv['issue_date'] == null
          ? null
          : DateTime.tryParse(inv['issue_date'] as String),
      notes: inv['notes'] as String?,
      publicToken: inv['public_token'] as String?,
      items: (items as List)
          .map((r) => InvoiceItem.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }

  /// Returns the hosted checkout URL to open in the system browser.
  ///
  /// Stripe Checkout deliberately opens externally rather than in a webview:
  /// card autofill, 3-D Secure and the bank's own app hand-off all work in the
  /// real browser and are unreliable inside an embedded one.
  Future<String> createCheckoutUrl(String publicToken) async {
    final res = await _db.functions.invoke('create-checkout-session', body: {
      'type': 'invoice',
      'public_token': publicToken,
      'success_url': 'https://ledgiproof.com/i/paid',
      'cancel_url': 'https://ledgiproof.com/i/$publicToken',
    });
    final data = res.data;
    final url = data is Map ? data['url'] as String? : null;
    if (url == null || url.isEmpty) {
      throw StateError('No checkout URL returned');
    }
    return url;
  }
}
