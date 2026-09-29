import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/books_service.dart';
import '../services/transactions_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import 'transaction_chat_screen.dart';

const _filters = ['all', 'blue', 'green', 'amber', 'red'];

String _filterLabel(String f) => switch (f) {
      'all' => 'All',
      'blue' => 'Blue',
      'green' => 'Green',
      'amber' => 'Amber',
      _ => 'Red',
    };

String _money(double v, String currency) {
  final sign = v < 0 ? '−' : (v > 0 ? '+' : '');
  final sym = currency == 'USD' ? '\$' : '$currency ';
  return '$sign$sym${v.abs().toStringAsFixed(2)}';
}

String _day(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

Color _semColor(String s) => semaphoreColors[s] ?? AppColors.inkMuted;

/// Every transaction of a workspace with the same semaphore filter as the web
/// (All / Blue / Green / Amber / Red, each with its count). Bank transactions
/// synced through Plaid appear here on their own: the screen listens for new
/// rows and refreshes, no pull needed.
///
/// A portal client sees the same screen read-only, with only their own
/// transactions -- the database narrows the rows, this screen just draws them.
class TransactionsScreen extends StatefulWidget {
  final Workspace workspace;

  /// Open already filtered, e.g. 'amber' when arriving from Review.
  final String initialFilter;
  const TransactionsScreen(
      {super.key, required this.workspace, this.initialFilter = 'all'});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with WidgetsBindingObserver {
  final _service = TransactionsService();
  final _books = BooksService();
  final _search = TextEditingController();
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _coalesce;
  bool _subscribedBefore = false;

  TxPage? _page; // last good page: never blanked by a reload
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  late String _filter = widget.initialFilter;
  TxPeriod _period = TxPeriod.days30;
  int _limit = 50;
  int _seq = 0;

  bool get _canReview =>
      !widget.workspace.isPortalClient &&
      const {'owner', 'admin', 'accountant', 'approver'}
          .contains(widget.workspace.role);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _coalesce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  /// New / changed transactions for this workspace. Bursts (a sync adds
  /// dozens of rows) collapse into one reload; a reconnect reloads too, since
  /// events may have been lost in the gap.
  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('transactions-${widget.workspace.orgId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'org_id',
            value: widget.workspace.orgId,
          ),
          callback: (_) {
            _coalesce?.cancel();
            _coalesce = Timer(const Duration(milliseconds: 400), () {
              if (mounted) _load();
            });
          },
        )
        .subscribe((status, _) {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          if (_subscribedBefore && mounted) _load();
          _subscribedBefore = true;
        });
  }

  /// Reloads what is on screen: the current filter and search, as many rows as
  /// the person had already scrolled through. Only the newest load may write.
  Future<void> _load() async {
    final seq = ++_seq;
    if (_page == null) setState(() => _loading = true);
    try {
      final page = await _service.load(
        widget.workspace.orgId,
        semaphore: _filter == 'all' ? null : _filter,
        search: _search.text,
        limit: _limit,
        period: _period,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _page = page;
        _error = null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _setFilter(String f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _limit = 50;
    });
    _load();
  }

  void _setPeriod(TxPeriod p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _limit = 50;
    });
    _load();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _limit = 50;
      _load();
    });
  }

  void _loadMore() {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _limit += 50;
    });
    _load();
  }

  Future<void> _open(TxItem tx) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _TxSheet(
        orgId: widget.workspace.orgId,
        tx: tx,
        canReview: _canReview,
        canAsk: !widget.workspace.isPortalClient,
        books: _books,
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final page = _page;
    if (page == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 30, color: AppColors.red),
            const SizedBox(height: 10),
            Text('Could not load transactions.',
                style: TextStyle(color: AppColors.ink)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── Dashboard header: what came in, what went out, what needs a look.
          Row(
            children: [
              Expanded(
                child: _Tile(
                  label: 'Money in',
                  value: _money(page.totals.moneyIn, 'USD').replaceFirst('+', ''),
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  label: 'Money out',
                  value: _money(-page.totals.moneyOut, 'USD').replaceFirst('−', ''),
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  label: 'To review',
                  value: '${page.totals.needsReview}',
                  color: page.totals.needsReview > 0 ? AppColors.amber : AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ColourBar(counts: page.counts),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in TxPeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.label),
                      selected: _period == p,
                      onSelected: (_) => _setPeriod(p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onChanged: _onSearch,
            decoration: const InputDecoration(
              hintText: 'Search merchant or description',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: f == 'all'
                          ? null
                          : Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _semColor(f),
                                shape: BoxShape.circle,
                              ),
                            ),
                      label: Text('${_filterLabel(f)} ${page.counts[f] ?? 0}'),
                      selected: _filter == f,
                      onSelected: (_) => _setFilter(f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Could not refresh. Showing what was loaded.',
                  style: TextStyle(fontSize: 12, color: AppColors.amber)),
            ),
          if (page.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  (page.counts['all'] ?? 0) == 0
                      ? 'No transactions in this period. Connect a bank account and they will appear here on their own.'
                      : 'Nothing matches.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkMuted),
                ),
              ),
            )
          else
            for (final tx in page.rows) _TxRow(tx: tx, onTap: () => _open(tx)),
          if (page.hasMore)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? 'Loading…' : 'Load more'),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Tile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      );
}

/// The four semaphore colours as one proportional bar: how the period's
/// transactions are spread between certified, reviewed, needs-review and
/// unusual, at a glance. Hidden while there is nothing to draw.
class _ColourBar extends StatelessWidget {
  final Map<String, int> counts;
  const _ColourBar({required this.counts});

  @override
  Widget build(BuildContext context) {
    final total = counts['all'] ?? 0;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final s in const ['blue', 'green', 'amber', 'red'])
              if ((counts[s] ?? 0) > 0)
                Expanded(
                  flex: counts[s]!,
                  child: Container(color: _semColor(s)),
                ),
          ],
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final TxItem tx;
  final VoidCallback onTap;
  const _TxRow({required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final incoming = tx.amount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: _semColor(tx.semaphore), shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _day(tx.date),
                        if (tx.isBank) 'Bank',
                        if (tx.clientName != null) tx.clientName!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(_money(tx.amount, tx.currency),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: incoming ? AppColors.green : AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TxSheet extends StatefulWidget {
  final String orgId;
  final TxItem tx;
  final bool canReview;
  final bool canAsk;
  final BooksService books;
  const _TxSheet({
    required this.orgId,
    required this.tx,
    required this.canReview,
    required this.canAsk,
    required this.books,
  });

  @override
  State<_TxSheet> createState() => _TxSheetState();
}

class _TxSheetState extends State<_TxSheet> {
  bool _busy = false;

  // LedgiProof's rule: blue verified by a person, green in the books and
  // ready to verify, amber needs a look, red a problem.
  String get _meaning => switch (widget.tx.semaphore) {
        'blue' => 'Verified',
        'green' => 'Ready to verify',
        'amber' => 'Needs a look',
        _ => 'Problem — needs a look',
      };

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await widget.books.verifyTransaction(widget.orgId, widget.tx.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify: ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final readyToVerify = tx.semaphore == 'green';
    final needsLook = tx.semaphore == 'amber' || tx.semaphore == 'red';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tx.title,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(_money(tx.amount, tx.currency),
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: tx.amount > 0 ? AppColors.green : AppColors.ink)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: _semColor(tx.semaphore), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(_meaning,
                  style: TextStyle(fontSize: 13, color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              _day(tx.date),
              if (tx.isBank) 'Bank feed',
              if (tx.clientName != null) tx.clientName!,
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          if ((tx.statusReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(tx.statusReason!,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 16),
          if (widget.canReview && needsLook)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Categorize it in Review to put it in the books; then it can be verified.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
            ),
          if (widget.canReview && readyToVerify)
            FilledButton.icon(
              onPressed: _busy ? null : _verify,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Verify',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (widget.canAsk)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TransactionChatScreen(
                    transactionId: tx.id,
                    transactionLabel: tx.title,
                  ),
                ));
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 17),
              label: const Text('Ask about this transaction'),
            ),
        ],
      ),
    );
  }
}
