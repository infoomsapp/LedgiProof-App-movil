import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/bill_service.dart';
import 'package:ledgiproof/services/review_service.dart';
import 'package:ledgiproof/utils/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Shapes from the live database after bills_ledger / error_codes.
void main() {
  group('vendor bills', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 'b1',
          'vendor_id': 'v1',
          'bill_number': 'A-1',
          'amount': 150,
          'due_date': '2026-10-15',
          'bill_date': '2026-09-01',
          'status': 'paid',
          'paid_at': '2026-09-28T00:00:00Z',
          'paid_amount': 150,
          ...extra,
        };

    test('paid by hand and not yet matched = in transit', () {
      final b = VendorBill.fromRow(row({'paid_via': 'manual', 'transaction_id': null}), {'v1': 'Acme'});
      expect(b.isPaid, isTrue);
      expect(b.isInTransit, isTrue);
      expect(b.billDate, DateTime(2026, 9, 1));
      expect(b.vendorName, 'Acme');
    });

    test('matched to the bank withdrawal, or paid from the bank feed = settled', () {
      expect(VendorBill.fromRow(row({'paid_via': 'manual', 'transaction_id': 't1'}), {}).isInTransit, isFalse);
      expect(VendorBill.fromRow(row({'paid_via': 'bank', 'transaction_id': 't2'}), {}).isInTransit, isFalse);
    });
  });

  group('review inbox bill matches', () {
    ReviewItem item(Map<String, dynamic> match) => ReviewItem.fromJson({
          'id': 't1',
          'transaction_date': '2026-09-10',
          'description': 'ACH ACME SUPPLY',
          'amount': -150,
          'currency': 'USD',
          'semaphore': 'green',
          'suggested_account_id': 'ap',
          'suggestion_source': match['kind'] == 'open' ? 'bill' : 'bill_payment',
          'suggestion_confidence': 95,
          'has_receipt': false,
          'invoice_match': null,
          'deposit_match': null,
          'bill_match': match,
        });

    test('an open bill', () {
      final m = item({'bill_id': 'b1', 'bill_number': 'A-1', 'vendor_name': 'Acme', 'kind': 'open'}).match!;
      expect(m.billId, 'b1');
      expect(m.billInTransit, isFalse);
      expect(m.label, 'Payment for bill A-1 · Acme');
    });

    test('a bill already marked paid (money in transit)', () {
      final m = item({'bill_id': 'b2', 'bill_number': null, 'vendor_name': 'Acme', 'kind': 'in_transit'}).match!;
      expect(m.billInTransit, isTrue);
      expect(m.label, 'Withdrawal of the payment for bill · Acme');
      expect(suggestionSourceLabel('bill_payment'), 'Recorded bill payment');
    });
  });

  group('friendlyError', () {
    test("shows LedgiProof's own coded message", () {
      const e = PostgrestException(
          message: 'Debits (10.00) and credits (9.00) must be equal — difference 1.00', code: 'LO010');
      expect(friendlyError(e), 'Debits (10.00) and credits (9.00) must be equal — difference 1.00');
    });

    test('still hides a raw database error', () {
      const e = PostgrestException(message: 'relation "x" does not exist', code: '42P01');
      expect(friendlyError(e, 'Could not load'), 'Could not load');
    });
  });
}
