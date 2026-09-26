import 'package:supabase_flutter/supabase_flutter.dart';

/// Sales tax for an invoice, worked out from where the client is so nobody has
/// to type a percentage. Same source as the web's "Auto-fill sales tax": the
/// `sales_tax_rates` reference table (public data, state-wide rates today).

const _stateNames = <String, String>{
  'ALABAMA': 'AL', 'ALASKA': 'AK', 'ARIZONA': 'AZ', 'ARKANSAS': 'AR',
  'CALIFORNIA': 'CA', 'COLORADO': 'CO', 'CONNECTICUT': 'CT', 'DELAWARE': 'DE',
  'DISTRICT OF COLUMBIA': 'DC', 'FLORIDA': 'FL', 'GEORGIA': 'GA', 'HAWAII': 'HI',
  'IDAHO': 'ID', 'ILLINOIS': 'IL', 'INDIANA': 'IN', 'IOWA': 'IA', 'KANSAS': 'KS',
  'KENTUCKY': 'KY', 'LOUISIANA': 'LA', 'MAINE': 'ME', 'MARYLAND': 'MD',
  'MASSACHUSETTS': 'MA', 'MICHIGAN': 'MI', 'MINNESOTA': 'MN', 'MISSISSIPPI': 'MS',
  'MISSOURI': 'MO', 'MONTANA': 'MT', 'NEBRASKA': 'NE', 'NEVADA': 'NV',
  'NEW HAMPSHIRE': 'NH', 'NEW JERSEY': 'NJ', 'NEW MEXICO': 'NM', 'NEW YORK': 'NY',
  'NORTH CAROLINA': 'NC', 'NORTH DAKOTA': 'ND', 'OHIO': 'OH', 'OKLAHOMA': 'OK',
  'OREGON': 'OR', 'PENNSYLVANIA': 'PA', 'RHODE ISLAND': 'RI', 'SOUTH CAROLINA': 'SC',
  'SOUTH DAKOTA': 'SD', 'TENNESSEE': 'TN', 'TEXAS': 'TX', 'UTAH': 'UT',
  'VERMONT': 'VT', 'VIRGINIA': 'VA', 'WASHINGTON': 'WA', 'WEST VIRGINIA': 'WV',
  'WISCONSIN': 'WI', 'WYOMING': 'WY',
};

/// "mD" / " md " / "Maryland" -> "MD". Null when it is not a US state. The
/// rates table is keyed by the upper-case two-letter code, and the state on a
/// client is free text, so without this "mD" finds no rate at all.
String? normalizeStateCode(String? raw) {
  final s = (raw ?? '').trim().toUpperCase();
  if (s.isEmpty) return null;
  if (s.length == 2) return _stateNames.containsValue(s) ? s : null;
  return _stateNames[s];
}

class SalesTaxRate {
  final double ratePct;
  final String jurisdiction;
  final String stateCode;
  const SalesTaxRate(this.ratePct, this.jurisdiction, this.stateCode);
}

/// The most specific rate in force on [date]: a ZIP-specific row beats a
/// state-wide one, the wanted category beats "general", newest start wins.
/// [rows] are `sales_tax_rates` rows already filtered to one state.
SalesTaxRate? pickSalesTaxRate(
  List<Map<String, dynamic>> rows, {
  required String stateCode,
  String? postal,
  String category = 'general',
  required DateTime date,
}) {
  final day = date.toIso8601String().substring(0, 10);
  final zip = (postal ?? '').trim();
  final ok = rows.where((r) {
    final from = (r['effective_from'] as String?) ?? '';
    final to = r['effective_to'] as String?;
    final rowZip = r['postal_code'] as String?;
    final cat = (r['category'] as String?) ?? 'general';
    return from.compareTo(day) <= 0 &&
        (to == null || to.compareTo(day) >= 0) &&
        (rowZip == null || rowZip == zip) &&
        (cat == category || cat == 'general');
  }).toList();
  if (ok.isEmpty) return null;
  ok.sort((a, b) {
    int flag(Map<String, dynamic> r, bool v) => v ? 1 : 0;
    final z = flag(b, b['postal_code'] != null) - flag(a, a['postal_code'] != null);
    if (z != 0) return z;
    final c = flag(b, b['category'] == category) - flag(a, a['category'] == category);
    if (c != 0) return c;
    return ((b['effective_from'] as String?) ?? '')
        .compareTo((a['effective_from'] as String?) ?? '');
  });
  final w = ok.first;
  return SalesTaxRate(
    (w['rate'] as num).toDouble(),
    (w['jurisdiction_name'] as String?) ?? stateCode,
    stateCode,
  );
}

/// What to offer for one client on one invoice.
class SalesTaxSuggestion {
  final SalesTaxRate? rate;

  /// The firm collects sales tax, so the rate is applied without asking.
  final bool autoApply;

  /// Why there is no rate, in words for the person composing.
  final String? reason;

  const SalesTaxSuggestion({this.rate, this.autoApply = false, this.reason});
}

class SalesTaxService {
  final _db = Supabase.instance.client;

  Future<SalesTaxSuggestion> suggestFor({
    required String orgId,
    required String clientId,
    DateTime? on,
  }) async {
    final client = await _db
        .from('clients')
        .select('display_name, state, postal_code, country, tax_exempt, tax_exempt_reason')
        .eq('id', clientId)
        .maybeSingle();
    if (client == null) {
      return const SalesTaxSuggestion(reason: 'Could not read the client.');
    }
    final name = (client['display_name'] as String?) ?? 'This client';
    if (client['tax_exempt'] == true) {
      final why = ((client['tax_exempt_reason'] as String?) ?? '').trim();
      return SalesTaxSuggestion(
          reason: '$name is tax exempt${why.isEmpty ? '' : ' ($why)'}, '
              'so no sales tax is added.');
    }
    final country = ((client['country'] as String?) ?? 'US').trim().toUpperCase();
    if (country != 'US' && country != 'USA' && country != 'UNITED STATES') {
      return const SalesTaxSuggestion(
          reason: 'Automatic sales tax covers US clients only.');
    }
    final state = normalizeStateCode(client['state'] as String?);
    if (state == null) {
      return SalesTaxSuggestion(
          reason: '$name has no state on file, so sales tax cannot be filled in.');
    }

    final rows = await _db
        .from('sales_tax_rates')
        .select('rate, jurisdiction_name, effective_from, effective_to, '
            'postal_code, category')
        .eq('country', 'US')
        .eq('state_code', state);
    final rate = pickSalesTaxRate(
      (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      stateCode: state,
      postal: client['postal_code'] as String?,
      date: on ?? DateTime.now(),
    );
    if (rate == null) {
      return SalesTaxSuggestion(reason: 'No sales-tax rate on file for $state.');
    }

    final settings = await _db
        .from('sales_tax_settings')
        .select('collects_sales_tax')
        .eq('org_id', orgId)
        .maybeSingle();
    return SalesTaxSuggestion(
      rate: rate,
      autoApply: settings?['collects_sales_tax'] == true,
    );
  }

  /// "Always add sales tax": turns on the firm-wide setting (the same one as
  /// Settings on the web), so new invoices fill their tax without asking.
  /// Only owner/admin/accountant may write it; the policy is the real gate.
  Future<void> setCollectsSalesTax(String orgId, bool on) async {
    final rows = await _db
        .from('sales_tax_settings')
        .upsert({
          'org_id': orgId,
          'collects_sales_tax': on,
          'updated_by': _db.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('org_id');
    if ((rows as List).isEmpty) {
      throw StateError('You do not have permission to change this setting.');
    }
  }
}
