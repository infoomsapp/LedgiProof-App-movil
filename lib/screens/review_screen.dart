import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/books_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';
import 'transaction_chat_screen.dart';

class ReviewScreen extends StatefulWidget {
  final Workspace workspace;
  const ReviewScreen({super.key, required this.workspace});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _books = BooksService();
  late Future<List<SemaphoreTx>> _queue;

  // Last queue that loaded. A reload (pull, or a new bank transaction arriving)
  // keeps showing it instead of swapping the list for a spinner.
  List<SemaphoreTx>? _last;
  RealtimeChannel? _channel;
  Timer? _coalesce;

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

  void _load() {
    _queue = _books.getReviewQueue(widget.workspace.orgId).then((r) {
      _last = r;
      return r;
    });
  }

  /// A bank transaction that needs a look can arrive at any moment (Plaid pushes
  /// it to the server, which saves it); the queue updates by itself. RLS decides
  /// which events this session receives.
  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('review-${widget.workspace.orgId}')
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
              if (mounted) setState(_load);
            });
          },
        )
        .subscribe();
  }

  /// Only staff whose role the transactions UPDATE policy accepts can review.
  /// A portal client sees the same amber/red rows (they are their own
  /// transactions) but cannot decide them, so no swipe is offered to them.
  bool get _canApprove =>
      !widget.workspace.isPortalClient &&
      const {'owner', 'admin', 'accountant', 'approver'}.contains(widget.workspace.role);

  Future<void> _approve(SemaphoreTx tx) async {
    try {
      await _books.approveTransaction(tx.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
      return;
    }
    if (!mounted) return;
    setState(_load);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Approved · ${tx.merchantName ?? tx.description ?? 'transaction'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Review is only what needs a decision (amber and red). The full list of
      // transactions has its own dashboard (Capture > Transactions, or a Home
      // quick action), so nothing about it lives here.
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
            if (items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: 80),
                  Icon(Icons.check_circle_outline, color: AppColors.green, size: 40),
                  SizedBox(height: 10),
                  Center(child: Text('Nothing needs review right now', style: TextStyle(color: AppColors.inkMuted))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final tx = items[i];
                return Dismissible(
                  key: ValueKey(tx.id),
                  direction: _canApprove ? DismissDirection.endToStart : DismissDirection.none,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: AppColors.greenBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.check, color: AppColors.green),
                  ),
                  confirmDismiss: (dir) async {
                    await _approve(tx);
                    return false; // list already reloads via setState
                  },
                  child: Container(
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
                                tx.semaphore == 'red'
                                    ? 'Unusual amount'
                                    : (_canApprove ? 'Needs your review' : 'Waiting on your accountant'),
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
