import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

class ReviewScreen extends StatefulWidget {
  final Workspace workspace;
  const ReviewScreen({super.key, required this.workspace});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _books = BooksService();
  late Future<List<SemaphoreTx>> _queue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _queue = _books.getReviewQueue(widget.workspace.orgId);
  }

  Future<void> _approve(SemaphoreTx tx) async {
    await _books.approveTransaction(tx.id);
    if (!mounted) return;
    setState(_load);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Approved · ${tx.merchantName ?? tx.description ?? 'transaction'}')),
    );
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
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Could not load the review queue.', style: TextStyle(color: AppColors.red)));
            }
            final items = snap.data ?? [];
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
                  direction: DismissDirection.endToStart,
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
                                tx.semaphore == 'red' ? 'Unusual amount' : 'Needs your review',
                                style: TextStyle(fontSize: 11, color: AppColors.inkSubtle),
                              ),
                            ],
                          ),
                        ),
                        Text('\$${tx.amount.abs().toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
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
