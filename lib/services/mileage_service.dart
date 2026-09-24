import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors src/lib/tax-tables-2026.ts businessMileageRateForDate exactly --
/// same string-compare cutover, so a trip logged here and one logged on the
/// web always land on the same rate for the same date.
double businessMileageRateForDate(String isoDate) {
  const cutover = '2026-07-01';
  const rateH1 = 0.725;
  const rateH2 = 0.760;
  return isoDate.compareTo(cutover) >= 0 ? rateH2 : rateH1;
}

/// Mirrors src/services/mileage.service.ts addMileageEntry -- same table,
/// same "snapshot the rate at save time" rule, same hardcoded
/// category: 'business' (the web service has no personal-mileage path
/// either -- mileage_entries is a deduction table, not a trip log; see
/// TripTrackerScreen for why a "Personal" trip is never written here).
class MileageService {
  final _db = Supabase.instance.client;

  Future<void> addMileageEntry({
    required String orgId,
    required String userId,
    required double miles,
    required String date, // ISO 'YYYY-MM-DD'
    String? purpose,
    String? clientId,
  }) async {
    final rate = businessMileageRateForDate(date);
    final deduction = (miles * rate * 100).round() / 100;

    await _db.from('mileage_entries').insert({
      'org_id': orgId,
      'client_id': clientId,
      'miles': miles,
      'entry_date': date,
      'purpose': purpose,
      'category': 'business',
      'rate': rate,
      'deduction': deduction,
      'created_by': userId,
      'source': 'manual',
    });
  }

  /// True when this org has an active ControlMiles connection -- the mobile
  /// UX design's rule: never show the in-app tracker to a connected user,
  /// since their trips already arrive automatically via mileage-webhook.
  Future<bool> hasActiveControlMilesConnection(String orgId) async {
    final row = await _db
        .from('mileage_connections')
        .select('id')
        .eq('org_id', orgId)
        .eq('status', 'active')
        .limit(1)
        .maybeSingle();
    return row != null;
  }
}
