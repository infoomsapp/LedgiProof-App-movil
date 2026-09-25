import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// One invoice with its line items, plus the online-payment path.
///
/// Mirrors the web's ClientInvoices/PortalInvoices pages and
/// stripe.service.ts's createInvoiceCheckoutSession: same edge function, same
/// body shape, same `type: 'invoice'` discriminator.
class InvoiceItem {
  final String description;
  final double quantity;
  final double unitPrice;
  final double discountPct;
  final double taxRate;
  final double lineTotal;

  InvoiceItem.fromRow(Map<String, dynamic> r)
      : description = (r['description'] as String?) ?? '',
        quantity = (r['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0,
        discountPct = (r['discount_pct'] as num?)?.toDouble() ?? 0,
        taxRate = (r['tax_rate'] as num?)?.toDouble() ?? 0,
        lineTotal = (r['line_total'] as num?)?.toDouble() ??
            ((r['quantity'] as num?)?.toDouble() ?? 0) *
                ((r['unit_price'] as num?)?.toDouble() ?? 0);
}

/// One payment recorded against an invoice (online or by hand).
class InvoicePayment {
  final double amount;
  final DateTime date;
  final String? method;
  final String? reference;
  final String? notes;

  InvoicePayment.fromRow(Map<String, dynamic> r)
      : amount = (r['amount'] as num?)?.toDouble() ?? 0,
        date = DateTime.tryParse((r['payment_date'] as String?) ?? '') ??
            DateTime.now(),
        method = r['method'] as String?,
        reference = r['reference'] as String?,
        notes = r['notes'] as String?;
}

/// The payment methods the invoice_payments CHECK constraint accepts, with the
/// label shown to a person. Sending anything else is rejected by the database.
const paymentMethods = <String, String>{
  'bank_transfer': 'Bank transfer / ACH',
  'check': 'Check',
  'cash': 'Cash',
  'credit_card': 'Card',
  'zelle': 'Zelle',
  'paypal': 'PayPal',
  'stripe': 'Stripe',
  'other': 'Other',
};

/// A row of the invoice list: just enough to read the status at a glance.
class InvoiceListItem {
  final String id;
  final String invoiceNumber;
  final String status;
  final double total;
  final double balanceDue;
  final String currency;
  final DateTime? dueDate;
  final String? clientName;

  InvoiceListItem.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        invoiceNumber = (r['invoice_number'] as String?) ?? '—',
        status = (r['status'] as String?) ?? 'draft',
        total = (r['total'] as num?)?.toDouble() ?? 0,
        balanceDue = (r['balance_due'] as num?)?.toDouble() ??
            (r['total'] as num?)?.toDouble() ??
            0,
        currency = (r['currency'] as String?) ?? 'USD',
        dueDate = r['due_date'] == null
            ? null
            : DateTime.tryParse(r['due_date'] as String),
        clientName = r['clients'] == null
            ? null
            : ((r['clients'] as Map)['company_name'] as String?) ??
                ((r['clients'] as Map)['display_name'] as String?);
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
  final String clientId;
  final String? clientName;
  final List<InvoiceItem> items;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double amountPaid;
  final DateTime? sentAt;
  final DateTime? viewedAt;
  final String? sentTo;
  final List<InvoicePayment> payments;

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
    required this.clientId,
    required this.clientName,
    required this.items,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.amountPaid = 0,
    this.sentAt,
    this.viewedAt,
    this.sentTo,
    this.payments = const [],
  });

  bool get isPaid => status == 'paid' || balanceDue <= 0;
  bool get isDraft => status == 'draft';
  bool get isVoid => status == 'void';

  /// Payment needs a public token, which is minted when an accountant marks
  /// the invoice sent. A portal client cannot mint one themselves: the
  /// invoices UPDATE policy requires owner/admin/accountant on the org, and a
  /// portal client holds no org role at all. So this is a real state to
  /// handle, not an edge case to paper over with a write that RLS rejects.
  bool get canPayOnline => !isPaid && !isDraft && !isVoid && publicToken != null;
}

/// One line the user is composing. Only the four fields the phone asks for;
/// discount and tax default at the database, exactly as they do on the web
/// when those fields are left alone.
class DraftItem {
  String description;
  double quantity;
  double unitPrice;

  /// Optional, percent (0-100). Same order the server uses: discount first,
  /// then tax on the discounted amount.
  double discountPct;
  double taxRate;

  DraftItem({
    this.description = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.discountPct = 0,
    this.taxRate = 0,
  });

  double get lineTotal =>
      quantity * unitPrice * (1 - discountPct / 100) * (1 + taxRate / 100);
  bool get isUsable => description.trim().isNotEmpty && quantity > 0;
}

class InvoiceService {
  final _db = Supabase.instance.client;

  /// Roles the invoices INSERT policy accepts. Checked before showing the
  /// compose action so the phone never offers a write RLS will reject; the
  /// policy remains the real gate.
  static const _canInvoiceRoles = {'owner', 'admin', 'accountant'};
  static bool canCreateInvoices(String role) => _canInvoiceRoles.contains(role);

  /// The public page a client opens to view and pay an invoice.
  static String publicUrl(String token) => 'https://app.ledgiproof.com/i/$token';

  /// Line rows exactly as the web's upsertItems writes them. Discount and tax
  /// are only sent when set, so an untouched line keeps the database defaults.
  List<Map<String, dynamic>> _itemRows(
      String invoiceId, String orgId, List<DraftItem> usable) {
    return [
      for (var i = 0; i < usable.length; i++)
        {
          'invoice_id': invoiceId,
          'org_id': orgId,
          'sort_order': i,
          'description': usable[i].description.trim(),
          'quantity': usable[i].quantity,
          'unit_price': usable[i].unitPrice,
          if (usable[i].discountPct > 0) 'discount_pct': usable[i].discountPct,
          if (usable[i].taxRate > 0) 'tax_rate': usable[i].taxRate,
        }
    ];
  }

  /// Creates the invoice as a DRAFT, then its items, then asks the database to
  /// recompute the totals -- the same three steps, in the same order, that
  /// invoice.service.ts's createInvoice + upsertItems perform. Totals are
  /// never computed on the phone: compute_invoice_totals owns that arithmetic
  /// so a mobile invoice and a desktop one can never disagree by a cent.
  Future<String> createDraft({
    required String orgId,
    required String clientId,
    required String dueDate, // ISO yyyy-MM-dd
    required List<DraftItem> items,
    String currency = 'USD',
    String? notes,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('No session');

    final number = await _db.rpc('next_invoice_number', params: {'p_org_id': orgId});

    // Non-USD invoices snapshot the rate at creation so a gain or loss can be
    // worked out when payment lands. Same call the web makes.
    double? fxRate;
    if (currency != 'USD') {
      final r = await _db.rpc('get_exchange_rate', params: {'p_currency': currency});
      fxRate = (r as num?)?.toDouble();
    }

    final inserted = await _db
        .from('invoices')
        .insert({
          'org_id': orgId,
          'client_id': clientId,
          'invoice_number': number as String,
          'due_date': dueDate,
          'notes': notes,
          'currency': currency,
          'fx_rate_at_creation': fxRate,
          'status': 'draft',
          'created_by': userId,
        })
        .select('id')
        .single();

    final invoiceId = inserted['id'] as String;

    final usable = items.where((i) => i.isUsable).toList();
    if (usable.isNotEmpty) {
      await _db.from('invoice_items').insert(_itemRows(invoiceId, orgId, usable));
    }
    await _db.rpc('compute_invoice_totals', params: {'p_invoice_id': invoiceId});
    return invoiceId;
  }

  /// Rewrites a DRAFT invoice: its header fields, then its lines, then the
  /// server-side total. Mirrors updateInvoice + upsertItems: the lines are
  /// deleted and reinserted rather than diffed, which is what the web does and
  /// what keeps sort_order honest without tracking per-row edits.
  ///
  /// Draft only, matching the web. Editing an invoice the client has already
  /// received would change a document they are holding; the status check here
  /// is a courtesy on top of that rule, not the enforcement -- a locked
  /// accounting period is refused by the database's own trigger either way.
  ///
  /// [clientId] may be changed while it is still a draft. `snapshot_bill_to`
  /// only freezes the client's billing details once the status leaves 'draft',
  /// so until then there is no snapshot for a reassignment to contradict --
  /// picking the wrong client on a draft is a typing mistake, not an
  /// accounting event.
  Future<void> updateDraft({
    required String invoiceId,
    required String orgId,
    required String dueDate,
    required List<DraftItem> items,
    String? clientId,
    String? notes,
  }) async {
    final current = await _db
        .from('invoices')
        .select('status')
        .eq('id', invoiceId)
        .single();
    if ((current['status'] as String?) != 'draft') {
      throw StateError('Only a draft can be edited.');
    }

    await _db.from('invoices').update({
      'due_date': dueDate,
      'notes': notes,
      'client_id': ?clientId,
    }).eq('id', invoiceId);

    await _db.from('invoice_items').delete().eq('invoice_id', invoiceId);

    final usable = items.where((i) => i.isUsable).toList();
    if (usable.isNotEmpty) {
      await _db.from('invoice_items').insert(_itemRows(invoiceId, orgId, usable));
    }
    await _db.rpc('compute_invoice_totals', params: {'p_invoice_id': invoiceId});
  }

  /// Marks the invoice sent and makes sure it carries a public token, which is
  /// what the pay link and the checkout session are built from. Mirrors
  /// markInvoiceSent(): an existing token is reused, never regenerated, so a
  /// link already in someone's inbox keeps working.
  Future<String> markSent(String invoiceId) async {
    final row = await _db
        .from('invoices')
        .select('public_token')
        .eq('id', invoiceId)
        .maybeSingle();
    final existing = row?['public_token'] as String?;
    final token = existing ?? const Uuid().v4().replaceAll('-', '');

    await _db.from('invoices').update({
      'status': 'sent',
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'public_token': token,
    }).eq('id', invoiceId);

    return token;
  }

  /// Emails the client their pay link. Kept separate from [markSent] for the
  /// same reason the web keeps them apart: marking sent has to stick even when
  /// the mail cannot go out, so the accountant still has a link to share by
  /// hand. Also the "send a reminder" action: the function re-sends the same
  /// pay link for any invoice that is not void.
  Future<void> sendEmail(String invoiceId) async {
    final res = await _db.functions
        .invoke('send-invoice-email', body: {'invoice_id': invoiceId});
    final data = res.data;
    final err = data is Map ? data['error'] as String? : null;
    if (err != null) throw StateError(err);
  }

  /// Every invoice of the workspace, newest first. RLS narrows this for a
  /// portal client to their own invoices, so one call serves both audiences.
  Future<List<InvoiceListItem>> listInvoices(String orgId, {int limit = 200}) async {
    final rows = await _db
        .from('invoices')
        .select('id, invoice_number, status, total, balance_due, currency, '
            'due_date, clients(display_name, company_name)')
        .eq('org_id', orgId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => InvoiceListItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<InvoiceDetail> getDetail(String invoiceId) async {
    final inv = await _db
        .from('invoices')
        .select('id, invoice_number, status, total, balance_due, currency, '
            'due_date, issue_date, notes, public_token, client_id, subtotal, '
            'discount_total, tax_total, amount_paid, sent_at, viewed_at, '
            'sent_to, clients(display_name, company_name)')
        .eq('id', invoiceId)
        .single();

    final items = await _db
        .from('invoice_items')
        .select('description, quantity, unit_price, discount_pct, tax_rate, '
            'line_total')
        .eq('invoice_id', invoiceId)
        .order('sort_order');

    final payments = await _db
        .from('invoice_payments')
        .select('amount, payment_date, method, reference, notes')
        .eq('invoice_id', invoiceId)
        .order('payment_date', ascending: false);

    DateTime? ts(Object? v) => v == null ? null : DateTime.tryParse('$v');
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;

    final total = n(inv['total']);
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
      clientId: inv['client_id'] as String,
      clientName: inv['clients'] == null
          ? null
          : ((inv['clients'] as Map)['company_name'] as String?) ??
              ((inv['clients'] as Map)['display_name'] as String?),
      items: (items as List)
          .map((r) => InvoiceItem.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(),
      subtotal: n(inv['subtotal']),
      discountTotal: n(inv['discount_total']),
      taxTotal: n(inv['tax_total']),
      amountPaid: n(inv['amount_paid']),
      sentAt: ts(inv['sent_at']),
      viewedAt: ts(inv['viewed_at']),
      sentTo: inv['sent_to'] as String?,
      payments: (payments as List)
          .map((r) =>
              InvoicePayment.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }

  /// Records a payment that happened outside the app (check, cash, transfer...)
  /// -- partial amounts allowed. Mirrors recordPayment(): insert the payment,
  /// then let compute_invoice_totals move the invoice to partial or paid. The
  /// amount is checked against the balance here so a typo cannot overpay, but
  /// the database CHECK (amount > 0) and the invoice_payments policy
  /// (owner/admin/accountant) remain the real gates.
  Future<void> recordPayment({
    required String invoiceId,
    required String orgId,
    required double amount,
    required double balanceDue,
    required DateTime date,
    required String method,
    String? reference,
    String? notes,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('No session');
    if (amount <= 0) throw StateError('Enter an amount greater than zero.');
    if (amount > balanceDue + 0.005) {
      throw StateError('That is more than the balance due.');
    }
    if (!paymentMethods.containsKey(method)) {
      throw StateError('Choose how it was paid.');
    }
    await _db.from('invoice_payments').insert({
      'invoice_id': invoiceId,
      'org_id': orgId,
      'amount': amount,
      'payment_date': date.toIso8601String().substring(0, 10),
      'method': method,
      if ((reference ?? '').trim().isNotEmpty) 'reference': reference!.trim(),
      if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      'recorded_by': userId,
    });
    await _db.rpc('compute_invoice_totals', params: {'p_invoice_id': invoiceId});
  }

  /// Voids an invoice. Refused here when money has already been paid against
  /// it: voiding would orphan those payments, and reversing a payment is a
  /// bookkeeping decision, not something a tap should do.
  Future<void> voidInvoice(String invoiceId) async {
    final row = await _db
        .from('invoices')
        .select('amount_paid')
        .eq('id', invoiceId)
        .single();
    if (((row['amount_paid'] as num?)?.toDouble() ?? 0) > 0) {
      throw StateError('This invoice has payments recorded, so it cannot be '
          'voided. Ask your bookkeeper to reverse the payment first.');
    }
    await _db.from('invoices').update({'status': 'void'}).eq('id', invoiceId);
  }

  /// A new DRAFT with the same client, lines and notes, due in 30 days. The
  /// original is untouched; the copy gets the next invoice number.
  Future<String> duplicate(InvoiceDetail source, {required String orgId}) {
    return createDraft(
      orgId: orgId,
      clientId: source.clientId,
      dueDate: DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String()
          .substring(0, 10),
      currency: source.currency,
      notes: source.notes,
      items: [
        for (final i in source.items)
          DraftItem(
            description: i.description,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
            discountPct: i.discountPct,
            taxRate: i.taxRate,
          ),
      ],
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
