// What goes onto the printed invoice is decided here: whose name it is billed
// to, which terms apply, and whether "how to pay" is offered.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/invoice_pdf_service.dart';
import 'package:ledgiproof/services/invoice_service.dart';

InvoiceDetail detail({
  String status = 'sent',
  double total = 1200,
  double paid = 0,
  String? token = 'tok123',
  List<InvoicePayment> payments = const [],
}) =>
    InvoiceDetail(
      id: 'i1',
      invoiceNumber: 'INV-0042',
      status: status,
      total: total,
      balanceDue: total - paid,
      currency: 'USD',
      dueDate: DateTime(2026, 10, 1),
      issueDate: DateTime(2026, 9, 1),
      notes: 'Thanks',
      publicToken: token,
      clientId: 'c1',
      clientName: 'Live Client Name',
      items: [
        InvoiceItem.fromRow({'description': 'Work', 'quantity': 2, 'unit_price': 600, 'line_total': 1200}),
      ],
      subtotal: total,
      amountPaid: paid,
      payments: payments,
    );

void main() {
  test('the frozen bill-to wins over the live client', () {
    final input = assembleInvoicePdfInput(
      detail(),
      invoiceRow: {
        'bill_to_snapshot_at': '2026-09-01T10:00:00Z',
        'bill_to_name': 'Ana Perez',
        'bill_to_company': 'Perez Design LLC',
        'bill_to_address_line1': '12 Main St',
        'bill_to_city': 'Austin',
        'bill_to_state': 'TX',
        'bill_to_postal_code': '78701',
        'bill_to_email': 'ana@example.com',
        'bill_to_tax_id': '12-3456789',
      },
      client: {'display_name': 'Somebody Else', 'email': 'else@example.com'},
      org: {'name': 'Acme'},
    );
    expect(input.billToLines, [
      'Ana Perez',
      'Perez Design LLC',
      '12 Main St',
      'Austin, TX 78701',
      'ana@example.com',
      'Tax ID 12-3456789',
    ]);
  });

  test('without a snapshot the live client is used, and empties are dropped', () {
    final input = assembleInvoicePdfInput(
      detail(),
      invoiceRow: {},
      client: {'display_name': 'Ana', 'company_name': 'Ana', 'address_line1': '  ', 'city': 'Miami', 'email': 'a@b.co'},
    );
    expect(input.billToLines, ['Ana', 'Miami', 'a@b.co']);
    // No client row at all still prints the name the invoice list shows.
    expect(assembleInvoicePdfInput(detail(), invoiceRow: {}).billToLines, ['Live Client Name']);
  });

  test('the invoice\'s own terms and footer beat the firm defaults', () {
    final org = {'name': 'Acme', 'invoice_terms': 'Net 30', 'invoice_footer': 'Firm footer'};
    final own = assembleInvoicePdfInput(detail(), invoiceRow: {'terms': 'Due on receipt', 'footer': ''}, org: org);
    expect(own.terms, 'Due on receipt');
    expect(own.footer, 'Firm footer'); // blank means "not set"
    final none = assembleInvoicePdfInput(detail(), invoiceRow: {});
    expect(none.terms, isNull);
    expect(none.orgName, 'Invoice');
  });

  test('pay link and instructions only while money is owed', () {
    final org = {'name': 'Acme', 'payment_instructions': 'Zelle'};
    final open = assembleInvoicePdfInput(detail(), invoiceRow: {}, org: org);
    expect(open.payUrl, 'https://app.ledgiproof.com/i/tok123');
    expect(open.paymentInstructions, 'Zelle');

    final paid = assembleInvoicePdfInput(detail(status: 'paid', paid: 1200), invoiceRow: {}, org: org);
    expect(paid.payUrl, isNull);
    expect(paid.paymentInstructions, isNull);

    final voided = assembleInvoicePdfInput(detail(status: 'void'), invoiceRow: {}, org: org);
    expect(voided.payUrl, isNull);

    final draft = assembleInvoicePdfInput(detail(status: 'draft', token: null), invoiceRow: {}, org: org);
    expect(draft.payUrl, isNull);
    expect(draft.paymentInstructions, isNull);
  });

  test('stored amounts and payment labels are carried over, not recomputed', () {
    final input = assembleInvoicePdfInput(
      detail(paid: 500, payments: [
        InvoicePayment.fromRow({'amount': 500, 'payment_date': '2026-09-10', 'method': 'bank_transfer', 'reference': 'R1'}),
        InvoicePayment.fromRow({'amount': 5, 'payment_date': '2026-09-11', 'method': null}),
      ]),
      invoiceRow: {},
    );
    expect(input.total, 1200);
    expect(input.amountPaid, 500);
    expect(input.balanceDue, 700);
    expect(input.lines.single.lineTotal, 1200);
    expect(input.payments.map((p) => p.method), ['Bank transfer / ACH', 'Payment']);
    expect(input.payments.first.reference, 'R1');
  });

  test('file names are safe', () {
    expect(invoicePdfFileName('INV-0042'), 'Invoice-INV-0042.pdf');
    expect(invoicePdfFileName('A/B: 7?'), 'Invoice-A-B-7.pdf');
    expect(invoicePdfFileName('***'), 'Invoice-document.pdf');
    expect(invoicePdfFileName('—'), 'Invoice-document.pdf');
  });
}
