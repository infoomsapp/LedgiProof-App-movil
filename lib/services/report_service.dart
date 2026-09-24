import 'package:supabase_flutter/supabase_flutter.dart';

/// Profit & Loss and Balance Sheet, straight from the same two RPCs the web's
/// Reports page calls. No arithmetic is repeated here beyond the two
/// sign conventions the shapes demand, so a report read on the phone and one
/// read at the desk are the same report.
class PlRow {
  final String code;
  final String name;
  final String type; // 'income' | 'expense'
  final double debit;
  final double credit;

  PlRow.fromRow(Map<String, dynamic> r)
      : code = (r['code'] as String?) ?? '',
        name = (r['name'] as String?) ?? '',
        type = (r['type'] as String?) ?? '',
        debit = (r['debit'] as num?)?.toDouble() ?? 0,
        credit = (r['credit'] as num?)?.toDouble() ?? 0;

  /// Income is credit-heavy and expense debit-heavy; the web applies exactly
  /// this pair of signs when it renders the same rows.
  double get amount => type == 'income' ? credit - debit : debit - credit;
}

class ProfitAndLoss {
  final List<PlRow> income;
  final List<PlRow> expenses;

  ProfitAndLoss({required this.income, required this.expenses});

  double get totalIncome => income.fold(0.0, (s, r) => s + r.amount);
  double get totalExpenses => expenses.fold(0.0, (s, r) => s + r.amount);
  double get netProfit => totalIncome - totalExpenses;
  bool get isEmpty => income.isEmpty && expenses.isEmpty;
}

class BsAccount {
  final String code;
  final String name;
  final int level;
  final double balance;

  BsAccount.fromRow(Map<String, dynamic> r)
      : code = (r['code'] as String?) ?? '',
        name = (r['name'] as String?) ?? '',
        level = (r['level'] as num?)?.toInt() ?? 1,
        balance = (r['balance'] as num?)?.toDouble() ?? 0;
}

class BsSection {
  final List<BsAccount> accounts;
  final double total;

  BsSection.fromJson(Map<String, dynamic>? j)
      : accounts = ((j?['accounts'] as List?) ?? [])
            .map((r) => BsAccount.fromRow(Map<String, dynamic>.from(r as Map)))
            .toList(),
        total = (j?['total'] as num?)?.toDouble() ?? 0;
}

class BalanceSheet {
  final BsSection assets;
  final BsSection liabilities;
  final BsSection equity;
  final double netIncome;
  final double difference;
  final bool balanced;

  BalanceSheet.fromJson(Map<String, dynamic> j)
      : assets = BsSection.fromJson(
            j['assets'] == null ? null : Map<String, dynamic>.from(j['assets'] as Map)),
        liabilities = BsSection.fromJson(
            j['liabilities'] == null ? null : Map<String, dynamic>.from(j['liabilities'] as Map)),
        equity = BsSection.fromJson(
            j['equity'] == null ? null : Map<String, dynamic>.from(j['equity'] as Map)),
        netIncome = (j['net_income'] as num?)?.toDouble() ?? 0,
        difference = (j['difference'] as num?)?.toDouble() ?? 0,
        balanced = (j['balanced'] as bool?) ?? false;

  bool get isEmpty =>
      assets.accounts.isEmpty &&
      liabilities.accounts.isEmpty &&
      equity.accounts.isEmpty;
}

class ReportService {
  final _db = Supabase.instance.client;

  Future<ProfitAndLoss> profitAndLoss({
    required String orgId,
    required int year,
    required int month,
    String? clientId,
  }) async {
    final data = await _db.rpc('get_profit_and_loss', params: {
      'p_org_id': orgId,
      'p_year': year,
      'p_month': month,
      'p_client_id': clientId,
    });
    final rows = ((data as List?) ?? [])
        .map((r) => PlRow.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
    return ProfitAndLoss(
      income: rows.where((r) => r.type == 'income').toList(),
      expenses: rows.where((r) => r.type == 'expense').toList(),
    );
  }

  Future<BalanceSheet> balanceSheet({
    required String orgId,
    required int year,
    required int month,
    String? clientId,
  }) async {
    final data = await _db.rpc('get_balance_sheet', params: {
      'p_org_id': orgId,
      'p_as_of_year': year,
      'p_as_of_month': month,
      'p_client_id': clientId,
    });
    return BalanceSheet.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
