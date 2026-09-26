import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/doc_format.dart';
import 'invoice_service.dart';

/// Recurring invoices and the payment-reminder policy.
///
/// Mirrors the web's recurring-invoice.service.ts: same tables, same generator
/// (`generate_due_recurring_invoices`), same rules. The database owns the
/// schedule arithmetic and the invoice numbers, so nothing is computed here
/// beyond a preview amount for the list.

enum RecurringFrequency { weekly, biweekly, monthly, quarterly, yearly }

extension RecurringFrequencyInfo on RecurringFrequency {
  String get dbValue => name;
  String get label => switch (this) {
        RecurringFrequency.weekly => 'Weekly',
        RecurringFrequency.biweekly => 'Every 2 weeks',
        RecurringFrequency.monthly => 'Monthly',
        RecurringFrequency.quarterly => 'Quarterly',
        RecurringFrequency.yearly => 'Yearly',
      };

  static RecurringFrequency parse(String? v) => RecurringFrequency.values
      .firstWhere((f) => f.name == v, orElse: () => RecurringFrequency.monthly);
}

enum RecurringStatus { active, paused, ended }

class RecurringInvoice {
  final String id;
  final String clientId;
  final String? clientName;
  final String? title;
  final String currency;
  final RecurringFrequency frequency;
  final DateTime nextRunDate;
  final DateTime? endDate;
  final int? maxOccurrences;
  final int occurrencesGenerated;
  final int netDays;
  final bool autoSend;
  final RecurringStatus status;

  /// What one generated invoice will total: quantity x price, less discount,
  /// plus tax, per line. A preview only -- the real total is computed by
  /// compute_invoice_totals when the invoice is generated.
  final double amount;

  RecurringInvoice.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String,
        clientId = r['client_id'] as String,
        clientName = r['clients'] is Map
            ? ((r['clients'] as Map)['company_name'] as String?) ??
                ((r['clients'] as Map)['display_name'] as String?)
            : null,
        title = r['title'] as String?,
        currency = (r['currency'] as String?) ?? 'USD',
        frequency = RecurringFrequencyInfo.parse(r['frequency'] as String?),
        nextRunDate = _date(r['next_run_date']) ?? DateTime.now(),
        endDate = _date(r['end_date']),
        maxOccurrences = (r['max_occurrences'] as num?)?.toInt(),
        occurrencesGenerated = (r['occurrences_generated'] as num?)?.toInt() ?? 0,
        netDays = (r['net_days'] as num?)?.toInt() ?? 30,
        autoSend = r['auto_send'] == true,
        status = RecurringStatus.values.firstWhere(
            (s) => s.name == r['status'],
            orElse: () => RecurringStatus.active),
        amount = _amount(r['recurring_invoice_items']);

  bool get isActive => status == RecurringStatus.active;

  /// "Monthly · next Oct 1, 2026", or how it stopped.
  String get scheduleLine => switch (status) {
        RecurringStatus.active =>
          '${frequency.label} · next ${formatDocDate(nextRunDate)}',
        RecurringStatus.paused => '${frequency.label} · paused',
        RecurringStatus.ended => '${frequency.label} · ended',
      };

  /// "3 of 12 sent" when it has a limit, "3 sent" otherwise, "" before the first.
  String get progress {
    if (maxOccurrences != null) {
      return '$occurrencesGenerated of $maxOccurrences created';
    }
    if (occurrencesGenerated == 0) return '';
    return '$occurrencesGenerated created';
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse('$v');

  static double _amount(Object? items) {
    if (items is! List) return 0;
    var sum = 0.0;
    for (final i in items) {
      if (i is! Map) continue;
      final q = (i['quantity'] as num?)?.toDouble() ?? 0;
      final p = (i['unit_price'] as num?)?.toDouble() ?? 0;
      final d = (i['discount_pct'] as num?)?.toDouble() ?? 0;
      final t = (i['tax_rate'] as num?)?.toDouble() ?? 0;
      sum += q * p * (1 - d / 100) * (1 + t / 100);
    }
    return (sum * 100).round() / 100;
  }
}

/// When payment-reminder emails go out. Off until a firm turns it on.
class ReminderPolicy {
  final bool enabled;
  final int daysBefore; // 0 = none
  final bool onDue;
  final List<int> overdueDays;

  const ReminderPolicy({
    this.enabled = false,
    this.daysBefore = 3,
    this.onDue = true,
    this.overdueDays = const [3, 7, 14],
  });

  ReminderPolicy.fromRow(Map<String, dynamic> r)
      : enabled = r['enabled'] == true,
        daysBefore = (r['days_before'] as num?)?.toInt() ?? 3,
        onDue = r['on_due'] != false,
        overdueDays = normalizeOverdueDays(
            (r['overdue_days'] as List?)?.map((e) => (e as num).toInt()) ??
                const [3, 7, 14]);

  ReminderPolicy copyWith({
    bool? enabled,
    int? daysBefore,
    bool? onDue,
    List<int>? overdueDays,
  }) =>
      ReminderPolicy(
        enabled: enabled ?? this.enabled,
        daysBefore: daysBefore ?? this.daysBefore,
        onDue: onDue ?? this.onDue,
        overdueDays: overdueDays ?? this.overdueDays,
      );

  /// "3 days before it is due, on the due date, and 3, 7 and 14 days after."
  String get summary {
    final parts = <String>[
      if (daysBefore > 0)
        '$daysBefore day${daysBefore == 1 ? '' : 's'} before it is due',
      if (onDue) 'on the due date',
      if (overdueDays.isNotEmpty) '${_joinNumbers(overdueDays)} days after',
    ];
    if (parts.isEmpty) return 'No reminders selected.';
    if (parts.length == 1) return '${_cap(parts.first)}.';
    return '${_cap(parts.sublist(0, parts.length - 1).join(', '))}, and ${parts.last}.';
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  static String _joinNumbers(List<int> n) {
    if (n.length == 1) return '${n.first}';
    return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
  }
}

/// Sorted, unique, 1..90, at most six -- exactly what the database accepts.
List<int> normalizeOverdueDays(Iterable<int> days) {
  final set = {for (final d in days) if (d >= 1 && d <= 90) d}.toList()..sort();
  return set.length > 6 ? set.sublist(0, 6) : set;
}

class RecurringInvoiceService {
  final _db = Supabase.instance.client;

  Future<List<RecurringInvoice>> list(String orgId) async {
    final rows = await _db
        .from('recurring_invoices')
        .select('id, client_id, title, currency, frequency, next_run_date, '
            'end_date, max_occurrences, occurrences_generated, net_days, '
            'auto_send, status, clients(display_name, company_name), '
            'recurring_invoice_items(quantity, unit_price, discount_pct, tax_rate)')
        .eq('org_id', orgId)
        .order('next_run_date');
    return (rows as List)
        .map((r) => RecurringInvoice.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Creates the schedule and its lines. If the lines cannot be saved the
  /// schedule is removed again: a schedule with no lines would go on
  /// generating empty invoices every period.
  Future<void> create({
    required String orgId,
    required String clientId,
    required RecurringFrequency frequency,
    required DateTime startDate,
    required int netDays,
    required bool autoSend,
    required List<DraftItem> items,
    String? title,
    String? notes,
    int? maxOccurrences,
  }) async {
    final usable = items.where((i) => i.isUsable).toList();
    if (usable.isEmpty) throw StateError('Add at least one line.');
    final start = startDate.toIso8601String().substring(0, 10);

    final row = await _db
        .from('recurring_invoices')
        .insert({
          'org_id': orgId,
          'client_id': clientId,
          'created_by': _db.auth.currentUser?.id,
          'title': _blankToNull(title),
          'notes': _blankToNull(notes),
          'frequency': frequency.dbValue,
          'start_date': start,
          'next_run_date': start,
          'net_days': netDays,
          'auto_send': autoSend,
          'max_occurrences': maxOccurrences,
        })
        .select('id')
        .single();
    final id = row['id'] as String;

    try {
      await _db.from('recurring_invoice_items').insert([
        for (var i = 0; i < usable.length; i++)
          {
            'recurring_id': id,
            'org_id': orgId,
            'sort_order': i,
            'description': usable[i].description.trim(),
            'quantity': usable[i].quantity,
            'unit_price': usable[i].unitPrice,
            'discount_pct': usable[i].discountPct,
            'tax_rate': usable[i].taxRate,
          }
      ]);
    } catch (_) {
      await _db.from('recurring_invoices').delete().eq('id', id);
      rethrow;
    }
  }

  Future<void> setStatus(String id, RecurringStatus status) async {
    final rows = await _db
        .from('recurring_invoices')
        .update({'status': status.name, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError('You do not have permission to change this schedule.');
    }
  }

  Future<void> delete(String id) async {
    final rows =
        await _db.from('recurring_invoices').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) {
      throw StateError('You do not have permission to delete this schedule.');
    }
  }

  /// Creates every invoice that is due today or earlier, now instead of at the
  /// next 6:00 UTC run. Returns how many were created.
  Future<int> generateDueNow(String orgId) async {
    final res = await _db
        .rpc('generate_due_recurring_invoices', params: {'p_org_id': orgId});
    if (res is Map && res['error'] != null) throw StateError('${res['error']}');
    return (res is Map ? (res['generated'] as num?)?.toInt() : null) ?? 0;
  }

  Future<ReminderPolicy> getReminderPolicy(String orgId) async {
    final row = await _db
        .from('invoice_reminder_settings')
        .select('enabled, days_before, on_due, overdue_days')
        .eq('org_id', orgId)
        .maybeSingle();
    return row == null
        ? const ReminderPolicy()
        : ReminderPolicy.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> saveReminderPolicy(String orgId, ReminderPolicy p) async {
    await _db.rpc('set_invoice_reminder_settings', params: {
      'p_org_id': orgId,
      'p_enabled': p.enabled,
      'p_days_before': p.daysBefore,
      'p_on_due': p.onDue,
      'p_overdue_days': normalizeOverdueDays(p.overdueDays),
    });
  }

  /// Whether a client has an email on file -- auto-send and reminders both
  /// need one, and finding out at 6am is too late.
  Future<bool> clientHasEmail(String clientId) async {
    final row = await _db
        .from('clients')
        .select('email')
        .eq('id', clientId)
        .maybeSingle();
    return ((row?['email'] as String?) ?? '').trim().isNotEmpty;
  }

  static String? _blankToNull(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? null : t;
  }
}
