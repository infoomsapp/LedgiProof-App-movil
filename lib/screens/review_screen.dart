import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/books_service.dart';
import '../services/review_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import '../widgets/client_picker_sheet.dart';
import '../widgets/pending_receipts_section.dart';
import '../widgets/verify_section.dart';
import 'transaction_chat_screen.dart';

/// The Review tab.
///
/// Staff get the "For review" inbox -- the same one-click loop as the web's
/// src/pages/ReviewInbox.tsx: every uncategorized bank transaction arrives
/// with a suggested category; confirming it posts the balanced entry (the
/// bank side is implied), turns it blue -- verified -- and teaches LedgiProof
/// the merchant. The second time a merchant lands in the same account, a rule
/// is offered. Red transactions are never part of "confirm all".
///
/// A portal client can't post to the books (get_review_queue and
/// post_reviewed_transactions are staff-only), so they keep the read-only
/// list of their own transactions that need a look.
class ReviewScreen extends StatelessWidget {
  final Workspace workspace;
  const ReviewScreen({super.key, required this.workspace});

  @override
  Widget build(BuildContext context) => workspace.isPortalClient
      ? _ClientReviewList(workspace: workspace)
      : _ReviewInbox(workspace: workspace);
}

// ── Staff: the "For review" inbox ────────────────────────────────────────────

class _ReviewInbox extends StatefulWidget {
  final Workspace workspace;
  const _ReviewInbox({required this.workspace});

  @override
  State<_ReviewInbox> createState() => _ReviewInboxState();
}

class _ReviewInboxState extends State<_ReviewInbox> {
  final _service = ReviewService();

  // Firm workspaces review one client's books at a time (accounts are per
  // client); null = the workspace's own books.
  String? _clientId;
  String? _clientName;

  ReviewQueue? _queue;
  List<CategoryAccount> _categories = [];
  final Map<String, Suggestion> _choices = {};
  final Set<String> _aiPending = {};
  final Set<String> _busy = {};
  final Map<String, String> _rowErrors = {};
  final List<RulePrompt> _prompts = [];
  int _postedSinceLoad = 0;
  int _receiptsRefresh = 0;
  String? _loadError;
  bool _loading = true;

  RealtimeChannel? _channel;
  Timer? _coalesce;

  /// Same roles post_reviewed_transactions accepts (the journal write policy).
  bool get _canPost => const {'owner', 'admin', 'accountant'}.contains(widget.workspace.role);

  String get _orgId => widget.workspace.orgId;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _coalesce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  /// New bank transactions (an import, a Plaid push) refresh the inbox by
  /// themselves. RLS decides which events this session receives.
  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('review-inbox-$_orgId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'org_id', value: _orgId),
          callback: (_) {
            _coalesce?.cancel();
            _coalesce = Timer(const Duration(milliseconds: 600), () {
              if (mounted && _busy.isEmpty) _load(quiet: true);
            });
          },
        )
        .subscribe();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final clientId = _clientId;
    try {
      final results = await Future.wait([
        _service.getQueue(_orgId, clientId),
        _service.getCategories(_orgId, clientId),
      ]);
      if (!mounted || clientId != _clientId) return;
      final queue = results[0] as ReviewQueue;
      final ids = queue.items.map((i) => i.id).toSet();
      setState(() {
        _queue = queue;
        _postedSinceLoad = 0;
        _categories = results[1] as List<CategoryAccount>;
        _loadError = null;
        _loading = false;
        // Keep what the user already picked for rows still in the inbox.
        _choices.removeWhere((id, _) => !ids.contains(id));
        for (final it in queue.items) {
          if (!_choices.containsKey(it.id) && it.suggestedAccountId != null) {
            _choices[it.id] = Suggestion(it.suggestedAccountId!, it.suggestionSource, it.suggestionConfidence,
                match: it.match);
          }
        }
      });

      // Whatever nothing else could suggest goes to the AI (up to 25 at once).
      final blank = queue.items.where((i) => !_choices.containsKey(i.id)).map((i) => i.id).take(25).toList();
      if (blank.isNotEmpty) {
        setState(() => _aiPending.addAll(blank));
        final ai = await _service.suggestWithAi(_orgId, clientId, blank);
        if (!mounted || clientId != _clientId) return;
        setState(() {
          _aiPending.removeAll(blank);
          ai.forEach((id, s) => _choices.putIfAbsent(id, () => s));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(e, 'Could not load the transactions to review.');
        _loading = false;
      });
    }
  }

  Future<void> _pickScope() async {
    final picked = await pickClient(context, orgId: _orgId);
    if (picked == null || !mounted) return;
    setState(() {
      _clientId = picked.id;
      _clientName = picked.displayName;
      _queue = null;
      _choices.clear();
      _rowErrors.clear();
      _prompts.clear();
    });
    await _load();
  }

  void _ownBooks() {
    setState(() {
      _clientId = null;
      _clientName = null;
      _queue = null;
      _choices.clear();
      _rowErrors.clear();
      _prompts.clear();
    });
    _load();
  }

  Future<void> _confirm(List<String> ids) async {
    final payload = [
      for (final id in ids)
        if (_choices[id] != null)
          {
            'transaction_id': id,
            'account_id': _choices[id]!.accountId,
            'source': _choices[id]!.source,
            'invoice_id': ?_choices[id]!.match?.invoiceId,
            'payment_id': ?_choices[id]!.match?.paymentId,
            'bill_id': ?_choices[id]!.match?.billId,
          },
    ];
    if (payload.isEmpty) return;
    setState(() => _busy.addAll(payload.map((p) => p['transaction_id'] as String)));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await _service.post(_orgId, payload);
      if (!mounted) return;
      setState(() {
        final q = _queue;
        if (q != null) {
          q.items.removeWhere((it) => res.posted.contains(it.id));
        }
        _postedSinceLoad += res.posted.length;
        for (final id in res.posted) {
          _rowErrors.remove(id);
          _choices.remove(id);
        }
        _rowErrors.addAll(res.failed);
        _prompts.addAll(res.rulePrompts);
      });
      final parts = [
        if (res.posted.isNotEmpty) '${res.posted.length} verified',
        if (res.failed.isNotEmpty) "${res.failed.length} couldn't be verified",
      ];
      if (parts.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, 'Could not verify the transactions.'))));
    } finally {
      if (mounted) setState(() => _busy.removeAll(payload.map((p) => p['transaction_id'] as String)));
    }
  }

  Future<void> _acceptRule(RulePrompt p) async {
    setState(() => _prompts.remove(p));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.setRule(_orgId, p);
      messenger.showSnackBar(const SnackBar(content: Text('Rule saved — it will be suggested first from now on')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, 'Could not save the rule.'))));
    }
  }

  Future<void> _chooseCategory(ReviewItem it) async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _CategorySheet(
        categories: _categories,
        moneyIn: it.moneyIn,
        selectedId: _choices[it.id]?.match == null ? _choices[it.id]?.accountId : null,
        match: it.match,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _choices[it.id] = picked is CategoryAccount
          ? Suggestion(picked.id, null, null)
          : Suggestion(it.suggestedAccountId!, it.suggestionSource, it.suggestionConfidence, match: it.match);
      _rowErrors.remove(it.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _queue;
    final items = q?.items ?? const <ReviewItem>[];
    final bulk = items.where((it) => _choices[it.id] != null && it.semaphore != 'red').map((it) => it.id).toList();
    final remaining = q == null ? 0 : q.total - _postedSinceLoad;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          remaining > 0 ? 'For review · $remaining' : 'For review',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () {
          setState(() => _receiptsRefresh++);
          return _load(quiet: true);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (widget.workspace.isFirm) _scopeBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Text(
                'Confirm in one tap. What you confirm turns blue — verified — and LedgiProof learns it: once a merchant is confirmed to the same account three times, it is categorized by itself.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
            ),
            if (_prompts.isNotEmpty) _rulePrompt(_prompts.first),
            if (q != null && !q.hasBankAccount && items.isNotEmpty)
              _banner(
                AppColors.amberBg,
                'Add a bank account first',
                'Your chart of accounts needs a bank or cash account for transactions to post against. Add one from the web app.',
              ),
            if (_canPost && bulk.isNotEmpty && (q?.hasBankAccount ?? false))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton(
                  onPressed: _busy.isEmpty ? () => _confirm(bulk) : null,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: Text(_busy.isEmpty ? 'Confirm all suggested (${bulk.length})' : 'Verifying…'),
                ),
              ),
            if (!_canPost && items.isNotEmpty)
              _banner(AppColors.surface2, 'View only', 'Your role can see these suggestions; an owner, admin or accountant confirms them.'),
            PendingReceiptsSection(
              orgId: _orgId,
              clientId: _clientId,
              canWrite: _canPost,
              refreshToken: _receiptsRefresh,
              onExpenseCreated: () => _load(quiet: true),
            ),
            VerifySection(
              orgId: _orgId,
              clientId: _clientId,
              canWrite: _canPost,
              refreshToken: _receiptsRefresh,
              onChanged: () => _load(quiet: true),
            ),
            if (_loading && q == null)
              const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()))
            else if (_loadError != null && q == null)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(child: Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.red))),
              )
            else if (items.isEmpty)
              _empty()
            else
              for (final it in items) ...[_row(it), const SizedBox(height: 8)],
            if (remaining > items.length && items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Showing the ${items.length} most recent of $remaining',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scopeBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickScope,
              icon: const Icon(Icons.business_outlined, size: 16),
              label: Text(
                _clientName ?? 'Your own books',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: BorderSide(color: AppColors.border),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
          if (_clientId != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: _ownBooks, child: const Text('Own books')),
          ],
        ],
      ),
    );
  }

  Widget _banner(Color bg, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
          const SizedBox(height: 3),
          Text(body, style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4)),
        ],
      ),
    );
  }

  Widget _rulePrompt(RulePrompt p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(color: AppColors.cyanBg, border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Always put “${p.merchantKey}” in ${p.accountName}?',
              style: TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w500)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => _prompts.remove(p)), child: const Text('Not now')),
              FilledButton(
                onPressed: () => _acceptRule(p),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Create rule'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 70),
      child: Column(
        children: [
          CircleAvatar(radius: 22, backgroundColor: AppColors.cyan, child: const Icon(Icons.check, color: Colors.white)),
          const SizedBox(height: 12),
          Text('All verified', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(
            'Nothing to review right now. Imported bank transactions show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _row(ReviewItem it) {
    final choice = _choices[it.id];
    final isBusy = _busy.contains(it.id);
    CategoryAccount? account;
    for (final c in _categories) {
      if (c.id == choice?.accountId) account = c;
    }
    final needsLook = it.semaphore == 'red' || it.semaphore == 'amber';
    final sourceLabel = suggestionSourceLabel(choice?.source);

    return Opacity(
      opacity: isBusy ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: semaphoreColors[it.semaphore], shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(it.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                ),
                const SizedBox(width: 8),
                Text(
                  '${it.moneyIn ? '+' : ''}${it.currency == 'USD' ? '\$' : '${it.currency} '}${it.amount.abs().toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: it.moneyIn ? AppColors.green : AppColors.ink),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: Row(
                children: [
                  Text(it.transactionDate, style: TextStyle(fontSize: 11, color: AppColors.inkSubtle)),
                  if (it.hasReceipt) ...[
                    const SizedBox(width: 6),
                    Tooltip(message: 'Receipt attached', child: Icon(Icons.receipt_long, size: 13, color: AppColors.cyan)),
                  ],
                  if (needsLook) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(it.statusReason ?? 'Take a look before confirming',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: semaphoreColors[it.semaphore])),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: isBusy || !_canPost ? null : () => _chooseCategory(it),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            choice?.match?.label ??
                                account?.label ??
                                (_aiPending.contains(it.id) ? 'AI is suggesting…' : 'Choose a category…'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: account != null || choice?.match != null ? AppColors.ink : AppColors.inkMuted),
                          ),
                          if ((account != null || choice?.match != null) && sourceLabel.isNotEmpty)
                            Text(
                              '${choice!.source == 'ai' ? '✦ ' : ''}$sourceLabel'
                              '${choice.confidence != null ? ' · ${choice.confidence}%' : ''}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: choice.source == 'rule' ? AppColors.cyan : AppColors.inkSubtle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (_canPost)
                  FilledButton(
                    onPressed: (account == null && choice?.match == null) || isBusy || !(_queue?.hasBankAccount ?? false)
                        ? null
                        : () => _confirm([it.id]),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(isBusy ? '…' : 'Confirm'),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.inkSubtle),
                  tooltip: 'Ask about this transaction',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TransactionChatScreen(transactionId: it.id, transactionLabel: it.label),
                  )),
                ),
              ],
            ),
            if (_rowErrors[it.id] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_rowErrors[it.id]!, style: TextStyle(fontSize: 11.5, color: AppColors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Searchable list of the scope's categories, the likely type first
/// (expenses for money out, income for money in).
class _CategorySheet extends StatefulWidget {
  final List<CategoryAccount> categories;
  final bool moneyIn;
  final String? selectedId;

  /// The row's invoice / recorded-payment match, offered first. Picking it
  /// pops the match itself instead of a [CategoryAccount].
  final DepositMatch? match;
  const _CategorySheet({required this.categories, required this.moneyIn, this.selectedId, this.match});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final match = widget.categories.where((c) => q.isEmpty || c.label.toLowerCase().contains(q)).toList();
    final first = widget.moneyIn ? 'income' : 'expense';
    final groups = [
      (first == 'income' ? 'Income' : 'Expenses', match.where((c) => c.type == first).toList()),
      (first == 'income' ? 'Expenses' : 'Income', match.where((c) => c.type != first).toList()),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(100))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search categories',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: widget.categories.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('This chart of accounts has no income or expense accounts yet.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkMuted)),
                  )
                : ListView(
                    controller: scroll,
                    children: [
                      if (widget.match != null && q.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text('MATCHES',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.inkSubtle, letterSpacing: 0.5)),
                        ),
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.receipt_long, color: AppColors.cyan, size: 18),
                          title: Text(widget.match!.label, style: TextStyle(color: AppColors.ink, fontSize: 13)),
                          trailing: widget.selectedId == null ? Icon(Icons.check, color: AppColors.cyan, size: 18) : null,
                          onTap: () => Navigator.of(ctx).pop(widget.match),
                        ),
                      ],
                      for (final (label, list) in groups)
                        if (list.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Text(label.toUpperCase(),
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.inkSubtle, letterSpacing: 0.5)),
                          ),
                          for (final c in list)
                            ListTile(
                              dense: true,
                              title: Text(c.label, style: TextStyle(color: AppColors.ink, fontSize: 13)),
                              trailing: c.id == widget.selectedId ? Icon(Icons.check, color: AppColors.cyan, size: 18) : null,
                              onTap: () => Navigator.of(ctx).pop(c),
                            ),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Portal client: read-only list of their own transactions needing a look ──

class _ClientReviewList extends StatefulWidget {
  final Workspace workspace;
  const _ClientReviewList({required this.workspace});

  @override
  State<_ClientReviewList> createState() => _ClientReviewListState();
}

class _ClientReviewListState extends State<_ClientReviewList> {
  final _books = BooksService();
  late Future<List<SemaphoreTx>> _queue;
  List<SemaphoreTx>? _last;
  int _refreshes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _refreshes++;
    _queue = _books.getReviewQueue(widget.workspace.orgId).then((r) {
      _last = r;
      return r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_load);
          await _queue;
        },
        child: FutureBuilder<List<SemaphoreTx>>(
          future: _queue,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && _last == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError && _last == null) {
              return Center(child: Text('Could not load the review queue.', style: TextStyle(color: AppColors.red)));
            }
            final items = snap.data ?? _last ?? [];
            // Their own scanned receipts that haven't found a bank line yet:
            // they can pick it or fix what was read (the firm records cash).
            final receipts = PendingReceiptsSection(
              orgId: widget.workspace.orgId,
              clientId: widget.workspace.portalClientId,
              canWrite: false,
              refreshToken: _refreshes,
            );
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  receipts,
                  const SizedBox(height: 60),
                  Icon(Icons.check_circle_outline, color: AppColors.green, size: 40),
                  const SizedBox(height: 10),
                  Center(child: Text('Nothing needs review right now', style: TextStyle(color: AppColors.inkMuted))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 0 : 8),
              itemBuilder: (context, i) {
                if (i == 0) return receipts;
                final tx = items[i - 1];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: semaphoreColors[tx.semaphore], shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx.merchantName ?? tx.description ?? 'Transaction',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                            const SizedBox(height: 2),
                            Text(
                              tx.semaphore == 'red' ? 'Unusual amount' : 'Waiting on your accountant',
                              style: TextStyle(fontSize: 11, color: AppColors.inkSubtle),
                            ),
                          ],
                        ),
                      ),
                      Text('\$${tx.amount.abs().toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.inkSubtle),
                        tooltip: 'Ask about this transaction',
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TransactionChatScreen(
                            transactionId: tx.id,
                            transactionLabel: tx.merchantName ?? tx.description ?? 'Transaction',
                          ),
                        )),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
