import 'package:flutter/material.dart';
import '../services/report_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// P&L and Balance Sheet for a month, from the same RPCs the web reads.
///
/// Both reports are per period, so the period picker sits above the toggle
/// rather than inside either report: changing the month should not throw away
/// which report you were looking at.
class ReportsScreen extends StatefulWidget {
  final Workspace workspace;
  const ReportsScreen({super.key, required this.workspace});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Report { pl, balanceSheet }

class _ReportsScreenState extends State<ReportsScreen> {
  final _service = ReportService();
  _Report _report = _Report.pl;
  late int _year;
  late int _month;
  Future<Object>? _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  void _load() {
    setState(() {
      _future = _report == _Report.pl
          ? _service.profitAndLoss(
              orgId: widget.workspace.orgId, year: _year, month: _month)
          : _service.balanceSheet(
              orgId: widget.workspace.orgId, year: _year, month: _month);
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
                Row(
                  children: [
                    Expanded(
                      child: _Toggle(
                        label: 'P&L',
                        selected: _report == _Report.pl,
                        onTap: () {
                          _report = _Report.pl;
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Toggle(
                        label: 'Balance Sheet',
                        selected: _report == _Report.balanceSheet,
                        onTap: () {
                          _report = _Report.balanceSheet;
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PeriodBar(
                  year: _year,
                  month: _month,
                  onChanged: (y, m) {
                    _year = y;
                    _month = m;
                    _load();
                  },
                ),
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
        title: 'Nothing posted for ${_months[_month - 1]} $_year.',
        body: 'A report only shows what has been entered and posted for the '
            'period. Try another month.',
        onRetry: _load,
      );
}

String _money(double v, String currency) {
  final sign = v < 0 ? '-' : '';
  final abs = v.abs().toStringAsFixed(2);
  return currency == 'USD' ? '$sign\$$abs' : '$sign$currency $abs';
}

class _PeriodBar extends StatelessWidget {
  final int year;
  final int month;
  final void Function(int year, int month) onChanged;
  const _PeriodBar(
      {required this.year, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              final m = month == 1 ? 12 : month - 1;
              onChanged(month == 1 ? year - 1 : year, m);
            },
            icon: Icon(Icons.chevron_left, color: AppColors.inkMuted),
            tooltip: 'Previous month',
          ),
          Expanded(
            child: Text(
              '${_months[month - 1]} $year',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
            ),
          ),
          IconButton(
            onPressed: () {
              final m = month == 12 ? 1 : month + 1;
              onChanged(month == 12 ? year + 1 : year, m);
            },
            icon: Icon(Icons.chevron_right, color: AppColors.inkMuted),
            tooltip: 'Next month',
          ),
        ],
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
