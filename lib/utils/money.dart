// Amounts arrive from the server as numbers with two decimals, which a double
// holds well enough to show. Adding doubles is what drifts, so every sum and
// comparison here goes through whole cents.

int toCents(num value) => (value * 100).round();

double fromCents(int cents) => cents / 100;

double sumMoney(Iterable<num> values) =>
    fromCents(values.fold(0, (sum, v) => sum + toCents(v)));

/// Miles (two decimals) times a rate (three decimals), to the cent, half up.
/// Same result as productCents in the server's mileage-webhook.
int mileageDeductionCents(num miles, num rate) {
  final product = (miles * 100).round() * (rate * 1000).round();
  return (product + 500) ~/ 1000;
}
