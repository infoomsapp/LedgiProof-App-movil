// The search box feeds a PostgREST or(...) filter. Anything that could close the
// filter or add a clause of its own must be neutralised before it gets there.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/transactions_service.dart';

void main() {
  String clean(String s) => TransactionsService.cleanSearchForTest(s);

  test('plain text passes through, trimmed and collapsed', () {
    expect(clean('  Amazon   Prime '), 'Amazon Prime');
  });

  test('characters that structure a filter are removed', () {
    expect(clean('a,merchant_name.eq.x'), isNot(contains(',')));
    expect(clean('x),(amount.gt.0'), isNot(anyOf(contains('('), contains(')'), contains(','))));
    expect(clean('100%'), '100');
    expect(clean('a*b'), 'a b');
    expect(clean(r'back\slash'), 'back slash');
  });

  test('nothing left means no search', () {
    expect(clean(' ,()% '), '');
  });

  test('rows parse the semaphore, sign and source', () {
    final t = TxItem.fromRow({
      'id': '1',
      'description': 'PAYROLL',
      'merchant_name': null,
      'amount': 250.5,
      'currency': 'USD',
      'semaphore': 'green',
      'transaction_date': '2026-09-20',
      'source': 'bank_api',
      'clients': {'display_name': 'Ana', 'company_name': 'Ana LLC'},
    });
    expect(t.title, 'PAYROLL');
    expect(t.isBank, isTrue);
    expect(t.amount, 250.5);
    expect(t.clientName, 'Ana LLC');
    expect(t.date, DateTime(2026, 9, 20));
  });
}
