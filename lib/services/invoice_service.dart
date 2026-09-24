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
  final String clientId;
  final String? clientName;
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
    required this.clientId,
    required this.clientName,
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

/// One line the user is composing. Only the four fields the phone asks for;
/// discount and tax default at the database, exactly as they do on the web
/// when those fields are left alone.
class DraftItem {
  String description;
  double quantity;
  double unitPrice;

  DraftItem({this.description = '', this.quantity = 1, this.unitPrice = 0});

  double get lineTotal => quantity * unitPrice;
  bool get isUsable => description.trim().isNotEmpty && quantity > 0;
}

class InvoiceService {
  final _db = Supabase.instance.client;

  /// Roles the invoices INSERT policy accepts. Checked before showing the
  /// compose action so the phone never offers a write RLS will reject; the
  /// policy remains the real gate.
  static const _canInvoiceRoles = {'owner', 'admin', 'accountant'};
  static bool canCreateInvoices(String role) => _canInvoiceRoles.contains(role);

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
      await _db.from('invoice_items').insert([
        for (var i = 0; i < usable.length; i++)
          {
            'invoice_id': invoiceId,
            'org_id': orgId,
            'sort_order': i,
            'description': usable[i].description.trim(),
            'quantity': usable[i].quantity,
            'unit_price': usable[i].unitPrice,
          }
      ]);
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
      await _db.from('invoice_items').insert([
        for (var i = 0; i < usable.length; i++)
          {
            'invoice_id': invoiceId,
            'org_id': orgId,
            'sort_order': i,
            'description': usable[i].description.trim(),
            'quantity': usable[i].quantity,
            'unit_price': usable[i].unitPrice,
          }
      ]);
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
  /// hand.
  Future<void> sendEmail(String invoiceId) async {
    final res = await _db.functions
        .invoke('send-invoice-email', body: {'invoice_id': invoiceId});
    final data = res.data;
    final err = data is Map ? data['error'] as String? : null;
    if (err != null) throw StateError(err);
  }

  Future<InvoiceDetail> getDetail(String invoiceId) async {
    final inv = await _db
        .from('invoices')
        .select('id, invoice_number, status, total, balance_due, currency, '
            'due_date, issue_date, notes, public_token, client_id, '
            'clients(display_name, company_name)')
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
      clientId: inv['client_id'] as String,
      clientName: inv['clients'] == null
          ? null
          : ((inv['clients'] as Map)['company_name'] as String?) ??
              ((inv['clients'] as Map)['display_name'] as String?),
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
