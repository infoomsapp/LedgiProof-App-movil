import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors src/services/time-entry.service.ts exactly -- same table, same
/// "duration computed and stored at stop time, never derived from now() on
/// read" rule, so a mobile-started timer and a web-started timer behave
/// identically and show up in the same list either app reads.
class TimeEntry {
  final String id;
  final String? clientId;
  final String? description;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationMinutes;

  TimeEntry.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        clientId = row['client_id'] as String?,
        description = row['description'] as String?,
        startedAt = row['started_at'] != null ? DateTime.parse(row['started_at'] as String) : null,
        endedAt = row['ended_at'] != null ? DateTime.parse(row['ended_at'] as String) : null,
        durationMinutes = row['duration_minutes'] as int?;
}

class TimeEntryService {
  final _db = Supabase.instance.client;

  /// Only one running timer per user is meaningful -- same non-enforcement
  /// note as the web service: working across two devices is a real,
  /// harmless case, not a bug worth blocking server-side.
  Future<TimeEntry> startTimer({
    required String orgId,
    required String userId,
    String? clientId,
    String? description,
  }) async {
    final row = await _db
        .from('time_entries')
        .insert({
          'org_id': orgId,
          'user_id': userId,
          'client_id': clientId,
          'description': description,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'hourly_rate': 0,
        })
        .select()
        .single();
    return TimeEntry.fromRow(row);
  }

  /// Stops a running timer, computing and storing its duration -- the same
  /// max(1, round(elapsed minutes)) rule as the web service.
  Future<TimeEntry> stopTimer(String id) async {
    final existing = await _db.from('time_entries').select('started_at').eq('id', id).single();
    final startedAt = DateTime.parse(existing['started_at'] as String);
    final minutes = ((DateTime.now().toUtc().difference(startedAt).inSeconds) / 60).round();
    final row = await _db
        .from('time_entries')
        .update({
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'duration_minutes': minutes < 1 ? 1 : minutes,
        })
        .eq('id', id)
        .select()
        .single();
    return TimeEntry.fromRow(row);
  }

  Future<TimeEntry?> getRunningTimer(String orgId, String userId) async {
    final row = await _db
        .from('time_entries')
        .select()
        .eq('org_id', orgId)
        .eq('user_id', userId)
        .isFilter('ended_at', null)
        .not('started_at', 'is', null)
        .maybeSingle();
    return row == null ? null : TimeEntry.fromRow(row);
  }
}
