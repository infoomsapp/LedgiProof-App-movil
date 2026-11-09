import '../utils/money.dart';

import 'package:flutter/material.dart';
import '../services/report_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../utils/report_period.dart';

/// P&L, Balance Sheet, Cash Flow and Budget for a month, a quarter or a year,
/// from the same RPCs the web reads.
///
/// Every report is per period, so the period picker sits above the toggle
/// rather than inside either report: changing the period should not throw
/// away which report you were looking at.
class ReportsScreen extends StatefulWidget {
  final Workspace workspace;
  const ReportsScreen({super.key, required this.workspace});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Report { pl, balanceSheet, cashFlow, budget }

class _ReportsScreenState extends State<ReportsScreen> {
  final _service = ReportService();
  _Report _report = _Report.pl;
  ReportPeriod _period = ReportPeriod.thisMonth();
  Future<Object>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// A client-portal workspace is one client inside the firm's org, and every
  /// report RPC matches on `client_id IS NOT DISTINCT FROM p_client_id` — so
  /// without this a portal user was reading the firm's own books instead of
  /// their own. Null for every other kind of workspace, which is the
  /// org-level scope those reports already used.
  String? get _clientId => widget.workspace.portalClientId;

  void _load() {
    setState(() {
      final p = _period;
      _future = switch (_report) {
        _Report.pl => _service.profitAndLoss(
            orgId: widget.workspace.orgId,
            from: p.from,
            to: p.to,
            clientId: _clientId),
        // A balance sheet is a position, not a movement: for a quarter or a
        // year it is the one at the period's last day.
        _Report.balanceSheet => _service.balanceSheet(
            orgId: widget.workspace.orgId,
            year: p.year,
            month: p.lastMonth,
            clientId: _clientId),
        _Report.cashFlow => _service.cashFlow(
            orgId: widget.workspace.orgId,
            from: p.from,
            to: p.to,
            clientId: _clientId),
        _Report.budget => _service.budgetVsActual(
            orgId: widget.workspace.orgId,
            from: p.from,
            to: p.to,
            clientId: _clientId),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                // Four labels do not fit one row at 360dp, and shrinking
                // them to fit is how a label ends up as 'Budget v...'. Two
                // rows of two, each still full width.
                Column(
                  children: [
                    for (final pair in const [
                      [(_Report.pl, 'P&L'), (_Report.balanceSheet, 'Balance Sheet')],
                      [
                        (_Report.cashFlow, 'Cash Flow'),
                        (_Report.budget, 'Budget')
                      ],
                    ]) ...[
                      Row(
                        children: [
                          for (final (r, label) in pair) ...[
                            Expanded(
                              child: _Toggle(
                                label: label,
                                selected: _report == r,
                                onTap: () {
                                  _report = r;
                                  _load();
                                },
                              ),
                            ),
                            if (r != pair.last.$1) const SizedBox(width: 6),
                          ],
                        ],
                      ),
                      if (pair.last.$1 != _Report.budget)
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _PeriodBar(
                  period: _period,
                  onChanged: (p) {
                    _period = p;
                    _load();
                  },
                ),
                if (_report == _Report.balanceSheet ||
                    _period.kind != PeriodKind.month) ...[
                  const SizedBox(height: 6),
                  Text(
                    _report == _Report.balanceSheet
                        ? 'As of ${_period.endLabel}'
                        : _period.span,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<Object>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _Empty(
                    icon: Icons.error_outline,
                    title: 'Could not load this report.',
                    body: friendlyError(snap.error!,
                        'Check your connection and try again.'),
                    onRetry: _load,
                  );
                }
                final data = snap.data;
                if (data is ProfitAndLoss) {
                  return data.isEmpty
                      ? _noData()
                      : _PlView(data: data, currency: 'USD');
                }
                if (data is BalanceSheet) {
                  return data.isEmpty
                      ? _noData()
                      : _BsView(data: data, currency: 'USD');
                }
                if (data is CashFlow) {
                  return data.isEmpty
                      ? _noData()
                      : _CfView(data: data, currency: 'USD');
                }
                if (data is BudgetVsActual) {
                  // 'No budget set' is not 'no data': the period may be full
                  // of posted expenses and simply have nothing to measure
                  // them against.
                  if (data.hasNoBudget) {
                    return _Empty(
                      icon: Icons.flag_outlined,
                      title: 'No budget set for ${_period.label}.',
                      body: 'Budgets are set on the web app, under Reports -> '
                          'Budget vs Actual. Once a monthly ceiling is set, '
                          'this report fills in and the assistant can warn '
                          'you before an expense puts the month over it.',
                      onRetry: _load,
                    );
                  }
                  return _BudgetView(data: data, currency: 'USD');
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _noData() => _Empty(
        icon: Icons.insights_outlined,
        title: 'Nothing posted for ${_period.label}.',
        body: 'A report only shows what has been entered and posted for the '
            'period. Try another ${_kindWord(_period.kind)}.',
        onRetry: _load,
      );
}

String _money(double v, String currency) {
  final sign = v < 0 ? '-' : '';
  final abs = v.abs().toStringAsFixed(2);
  return currency == 'USD' ? '$sign\$$abs' : '$sign$currency $abs';
}

String _kindWord(PeriodKind k) => switch (k) {
      PeriodKind.month => 'month',
      PeriodKind.quarter => 'quarter',
      PeriodKind.year => 'year',
    };

/// Month / Quarter / Year, then the period itself: the arrows step one
/// period, and tapping the name opens the calendar to jump anywhere.
class _PeriodBar extends StatelessWidget {
  final ReportPeriod period;
  final void Function(ReportPeriod period) onChanged;
  const _PeriodBar({required this.period, required this.onChanged});

  Future<void> _openCalendar(BuildContext context) async {
    final picked = await showModalBottomSheet<ReportPeriod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _PeriodCalendar(initial: period),
    );
    if (picked != null && !picked.sameAs(period)) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KindChips(
          kind: period.kind,
          onChanged: (k) => onChanged(period.withKind(k)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => onChanged(period.step(-1)),
                icon: Icon(Icons.chevron_left, color: AppColors.inkMuted),
                tooltip: 'Previous ${_kindWord(period.kind)}',
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openCalendar(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month_outlined,
                            size: 16, color: AppColors.inkMuted),
                        const SizedBox(width: 6),
                        Text(
                          period.label,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onChanged(period.step(1)),
                icon: Icon(Icons.chevron_right, color: AppColors.inkMuted),
                tooltip: 'Next ${_kindWord(period.kind)}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindChips extends StatelessWidget {
  final PeriodKind kind;
  final void Function(PeriodKind kind) onChanged;
  const _KindChips({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final (k, label) in const [
            (PeriodKind.month, 'Month'),
            (PeriodKind.quarter, 'Quarter'),
            (PeriodKind.year, 'Year'),
          ])
            Expanded(
              child: Material(
                color: kind == k ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: kind == k ? null : () => onChanged(k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: kind == k ? AppColors.ink : AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The calendar: a year of months, a year of quarters, or a page of years.
/// Picking a cell closes the sheet and returns that period.
class _PeriodCalendar extends StatefulWidget {
  final ReportPeriod initial;
  const _PeriodCalendar({required this.initial});

  @override
  State<_PeriodCalendar> createState() => _PeriodCalendarState();
}

class _PeriodCalendarState extends State<_PeriodCalendar> {
  late PeriodKind _kind = widget.initial.kind;

  /// The year shown (months and quarters), or the last year on the page of
  /// years -- which ends at this year or the chosen one, whichever is later,
  /// so both are on it.
  late int _year = widget.initial.kind == PeriodKind.year &&
          widget.initial.year < DateTime.now().year
      ? DateTime.now().year
      : widget.initial.year;

  final _today = DateTime.now();

  static const _yearsPerPage = 12;

  void _pick(ReportPeriod p) => Navigator.of(context).pop(p);

  Widget _cell({
    required String title,
    String? subtitle,
    required bool selected,
    required bool current,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: current && !selected ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.ink)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.85)
                            : AppColors.inkMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(int columns, double aspect, List<Widget> cells) => GridView.count(
        crossAxisCount: columns,
        childAspectRatio: aspect,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cells,
      );

  @override
  Widget build(BuildContext context) {
    final sel = widget.initial;
    final String header;
    final int stepBy;
    final Widget grid;
    switch (_kind) {
      case PeriodKind.month:
        header = '$_year';
        stepBy = 1;
        grid = _grid(4, 1.6, [
          for (var m = 1; m <= 12; m++)
            _cell(
              title: monthNames[m - 1].substring(0, 3),
              selected: sel.kind == PeriodKind.month && sel.year == _year && sel.month == m,
              current: _today.year == _year && _today.month == m,
              onTap: () => _pick(ReportPeriod(PeriodKind.month, _year, m)),
            ),
        ]);
      case PeriodKind.quarter:
        header = '$_year';
        stepBy = 1;
        grid = _grid(2, 2.2, [
          for (var q = 1; q <= 4; q++)
            _cell(
              title: 'Q$q',
              subtitle: '${monthNames[(q - 1) * 3].substring(0, 3)} – '
                  '${monthNames[q * 3 - 1].substring(0, 3)}',
              selected: sel.kind == PeriodKind.quarter && sel.year == _year && sel.quarter == q,
              current: _today.year == _year && (_today.month - 1) ~/ 3 + 1 == q,
              onTap: () => _pick(ReportPeriod(PeriodKind.quarter, _year, (q - 1) * 3 + 1)),
            ),
        ]);
      case PeriodKind.year:
        final first = _year - _yearsPerPage + 1;
        header = '$first – $_year';
        stepBy = _yearsPerPage;
        grid = _grid(4, 1.6, [
          for (var y = first; y <= _year; y++)
            _cell(
              title: '$y',
              selected: sel.kind == PeriodKind.year && sel.year == y,
              current: _today.year == y,
              onTap: () => _pick(ReportPeriod(PeriodKind.year, y, 1)),
            ),
        ]);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a period',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 12),
            _KindChips(
              kind: _kind,
              onChanged: (k) => setState(() {
                _kind = k;
                // The page of years ends at the selected year or this one,
                // whichever is later, so this year is always on it.
                _year = k == PeriodKind.year
                    ? (sel.year > _today.year ? sel.year : _today.year)
                    : sel.year;
              }),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _year -= stepBy),
                  icon: Icon(Icons.chevron_left, color: AppColors.inkMuted),
                  tooltip: 'Earlier',
                ),
                Expanded(
                  child: Text(header,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                ),
                IconButton(
                  onPressed: () => setState(() => _year += stepBy),
                  icon: Icon(Icons.chevron_right, color: AppColors.inkMuted),
                  tooltip: 'Later',
                ),
              ],
            ),
            const SizedBox(height: 8),
            grid,
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _pick(ReportPeriod(_kind, _today.year, _today.month)),
              child: Text('This ${_kindWord(_kind)}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Toggle(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.inkMuted),
          ),
        ),
      ),
    );
  }
}

class _PlView extends StatelessWidget {
  final ProfitAndLoss data;
  final String currency;
  const _PlView({required this.data, required this.currency});

  @override
  Widget build(BuildContext context) {
    final profit = data.netProfit >= 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _Headline(
          label: profit ? 'Net profit' : 'Net loss',
          value: _money(data.netProfit, currency),
          color: profit ? AppColors.green : AppColors.red,
        ),
        const SizedBox(height: 16),
        _Group(
          title: 'Income',
          rows: [for (final r in data.income) (r.code, r.name, r.amount)],
          total: data.totalIncome,
          accent: AppColors.green,
          currency: currency,
        ),
        const SizedBox(height: 12),
        _Group(
          title: 'Expenses',
          rows: [for (final r in data.expenses) (r.code, r.name, r.amount)],
          total: data.totalExpenses,
          accent: AppColors.red,
          currency: currency,
        ),
      ],
    );
  }
}

class _BsView extends StatelessWidget {
  final BalanceSheet data;
  final String currency;
  const _BsView({required this.data, required this.currency});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // Whether the sheet balances is the first thing an accountant checks,
        // so it leads rather than hiding at the bottom.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: data.balanced ? AppColors.greenBg : AppColors.redBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                  data.balanced
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 18,
                  color: data.balanced ? AppColors.green : AppColors.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.balanced
                      ? 'Balanced'
                      : 'Out by ${_money(data.difference, currency)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: data.balanced ? AppColors.green : AppColors.red),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Group(
          title: 'Assets',
          rows: [
            for (final a in data.assets.accounts) (a.code, a.name, a.balance)
          ],
          total: data.assets.total,
          accent: AppColors.primary,
          currency: currency,
        ),
        const SizedBox(height: 12),
        _Group(
          title: 'Liabilities',
          rows: [
            for (final a in data.liabilities.accounts)
              (a.code, a.name, a.balance)
          ],
          total: data.liabilities.total,
          accent: AppColors.amber,
          currency: currency,
        ),
        const SizedBox(height: 12),
        _Group(
          title: 'Equity',
          rows: [
            for (final a in data.equity.accounts) (a.code, a.name, a.balance)
          ],
          total: data.equity.total,
          accent: AppColors.cyan,
          currency: currency,
        ),
      ],
    );
  }
}

class _CfView extends StatelessWidget {
  final CashFlow data;
  final String currency;
  const _CfView({required this.data, required this.currency});

  @override
  Widget build(BuildContext context) {
    final up = data.netChange >= 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // The reconciliation leads, because it is the one thing that says
        // whether the rest of this screen can be trusted.
        if (!data.reconciles)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.amberBg,
              border: Border.all(color: AppColors.amber),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_outlined, size: 17, color: AppColors.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This statement does not reconcile. The movements below '
                    'explain ${_money(data.netChange, currency)} but cash actually '
                    'moved ${_money(data.actualChange, currency)}. Usually one '
                    'account is classified wrongly.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
        _Headline(
          label: up ? 'Cash increased' : 'Cash decreased',
          value: _money(data.netChange, currency),
          color: up ? AppColors.green : AppColors.red,
        ),
        const SizedBox(height: 16),
        _Group(
          title: 'Summary',
          rows: [
            ('', 'Net income', data.netIncome),
            ('', 'Operating activities', data.operating),
            ('', 'Investing activities', data.investing),
            ('', 'Financing activities', data.financing),
          ],
          total: data.netChange,
          accent: AppColors.primary,
          currency: currency,
        ),
        const SizedBox(height: 12),
        _Group(
          title: 'Cash position',
          rows: [
            ('', 'Start of period', data.cashStart),
            ('', 'End of period', data.cashEnd),
          ],
          total: data.actualChange,
          accent: AppColors.cyan,
          currency: currency,
        ),
        if (data.lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Group(
            title: 'What moved',
            rows: [
              for (final l in data.lines) (l.code, '${l.name}  ·  ${l.bucket}', l.amount)
            ],
            total: sumMoney(data.lines.map((l) => l.amount)),
            accent: AppColors.amber,
            currency: currency,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          data.cashAccounts.isEmpty
              ? 'No account is marked as cash, so this statement cannot reconcile.'
              : 'Cash accounts: ${data.cashAccounts.join(', ')}',
          style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle),
        ),
      ],
    );
  }
}

/// Budget vs Actual. The monthly ceiling leads, because it is the one figure
/// the assistant checks a new expense against; the per-account lines below it
/// are the breakdown, never added to it.
class _BudgetView extends StatelessWidget {
  final BudgetVsActual data;
  final String currency;
  const _BudgetView({required this.data, required this.currency});

  @override
  Widget build(BuildContext context) {
    final over = data.overCeiling;
    final oneMonth = data.months == 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        // Budgets are set month by month: over a quarter or a year, say when
        // only some of the months have one, so the spending is not read
        // against a budget that covers less time than it does.
        if (!oneMonth && data.budgetedMonths < data.months)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.amberBg,
              border: Border.all(color: AppColors.amber),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'A budget is set for ${data.budgetedMonths} of the '
              '${data.months} months. Spending covers all ${data.months}.',
              style: TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
        if (data.periodBudget > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: over ? AppColors.redBg : AppColors.greenBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (over ? AppColors.red : AppColors.green)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        oneMonth
                            ? (over
                                ? 'Over the monthly ceiling'
                                : 'Within the monthly ceiling')
                            : (over
                                ? 'Over the ceiling'
                                : 'Within the ceiling'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: over ? AppColors.red : AppColors.green,
                        ),
                      ),
                    ),
                    Text(
                      '${_money(data.ceilingLeft.abs(), currency)}'
                      '${over ? ' over' : ' left'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: over ? AppColors.red : AppColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Spent ${_money(data.totalActual, currency)} of '
                  '${_money(data.periodBudget, currency)} budgeted '
                  '${oneMonth ? 'for the month' : 'across these ${data.months} months'}.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        if (data.periodBudget > 0) const SizedBox(height: 16),
        for (final l in data.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.code}  ${l.name}',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                    Text(
                      l.hasBudget
                          ? '${_money(l.remaining.abs(), currency)}'
                              '${l.isOver ? ' over' : ' left'}'
                          : _money(l.actual, currency),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: !l.hasBudget
                            ? AppColors.inkMuted
                            : l.isOver
                                ? AppColors.red
                                : AppColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l.hasBudget
                      ? '${_money(l.actual, currency)} of '
                          '${_money(l.budget, currency)}'
                          '${l.overPct == null ? '' : '  ·  '
                              '${l.overPct! > 0 ? '+' : ''}'
                              '${l.overPct!.toStringAsFixed(1)}%'}'
                      : 'Not budgeted',
                  style:
                      TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: AppColors.border),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Totals',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            Text(
              '${_money(data.totalActual, currency)} of '
              '${_money(data.totalBudget, currency)}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Actuals come from the same journal entries as the P&L. Accounts '
          'with no budget are listed when they spent something, so '
          'unbudgeted spending is visible rather than missing.',
          style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Headline(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.inkSubtle)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<(String, String, double)> rows;
  final double total;
  final Color accent;
  final String currency;

  const _Group({
    required this.title,
    required this.rows,
    required this.total,
    required this.accent,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    // A chart of accounts has many accounts that never moved; showing every
    // zero would bury the handful that did, which is why the web hides them
    // too.
    final nonZero = rows.where((r) => r.$3 != 0).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: accent)),
          ),
          if (nonZero.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text('Nothing in this section for the period.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSubtle)),
            )
          else
            for (final r in nonZero)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(r.$1,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: AppColors.inkSubtle)),
                    ),
                    Expanded(
                      child: Text(r.$2,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.inkMuted)),
                    ),
                    Text(_money(r.$3, currency),
                        style:
                            TextStyle(fontSize: 13, color: AppColors.ink)),
                  ],
                ),
              ),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text('Total',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const Spacer(),
                Text(_money(total, currency),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onRetry;
  const _Empty(
      {required this.icon,
      required this.title,
      required this.body,
      required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.inkSubtle),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}
