/// Which cards the Home "Quick actions" row shows, and in what order.
///
/// The person can pick and reorder them, so what is saved is just a list of
/// action ids. Everything that can go wrong with a saved list -- an id that no
/// longer exists, one that this workspace cannot use (mileage in a firm, Bills
/// for a client), duplicates, too many, an empty list -- is settled here, in
/// one place that has no Flutter in it, so it can be tested.
library;

/// The row holds this many cards; more would not fit on a phone.
const maxQuickActions = 5;

/// Order of preference when nothing was saved: the four capture actions people
/// already had, then Transactions and the shortcuts that were never on Home.
const defaultQuickActionOrder = [
  'scan_receipt',
  'log_time',
  'log_trip',
  'manual_expense',
  'transactions',
  'invoices',
  'bills',
];

/// What a workspace with no saved choice shows: the first [maxQuickActions] of
/// [defaultQuickActionOrder] that are [available] there.
List<String> defaultQuickActions(List<String> available) => [
      for (final id in defaultQuickActionOrder)
        if (available.contains(id)) id,
    ].take(maxQuickActions).toList();

/// Turns a saved list into the list to show.
///
/// [saved] is null when nothing was ever saved. Ids that are not [available]
/// are dropped (a saved "Bills" must not appear for someone who cannot use it),
/// duplicates collapse, the result is capped at [maxQuickActions], and if
/// nothing usable is left the defaults are used -- the row is never empty.
List<String> resolveQuickActions({
  required List<String>? saved,
  required List<String> available,
}) {
  if (saved == null) return defaultQuickActions(available);
  final seen = <String>{};
  final kept = <String>[
    for (final id in saved)
      if (available.contains(id) && seen.add(id)) id,
  ].take(maxQuickActions).toList();
  return kept.isEmpty ? defaultQuickActions(available) : kept;
}

/// The order the edit sheet lists every action in: the chosen ones first, in
/// their order, then the rest in default order.
List<String> editListOrder({
  required List<String> chosen,
  required List<String> available,
}) =>
    [
      ...chosen,
      for (final id in defaultQuickActionOrder)
        if (available.contains(id) && !chosen.contains(id)) id,
      // Any available id the default order does not know about, last.
      for (final id in available)
        if (!chosen.contains(id) && !defaultQuickActionOrder.contains(id)) id,
    ];
