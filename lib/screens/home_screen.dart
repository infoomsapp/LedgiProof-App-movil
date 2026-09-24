import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/capture_sheet.dart';

class HomeScreen extends StatefulWidget {
  final Workspace workspace;
  const HomeScreen({super.key, required this.workspace});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _books = BooksService();
  late Future<List<SemaphoreTx>> _queue;

  @override
  void initState() {
    super.initState();
    _queue = _books.getReviewQueue(widget.workspace.orgId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workspace.orgName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _queue = _books.getReviewQueue(widget.workspace.orgId));
          await _queue;
        },
        child: FutureBuilder<List<SemaphoreTx>>(
          future: _queue,
          builder: (context, snap) {
            final count = snap.data?.length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NEEDS YOUR EYES',
                          style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      Text(
                        count == null ? '—' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('QUICK ACTIONS',
                    style: TextStyle(color: AppColors.inkSubtle, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 10),
                Row(
                  children: captureActions
                      .map((a) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => showCaptureSheet(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(a.icon, size: 18, color: AppColors.primaryInk),
                                      const SizedBox(height: 4),
                                      Text(a.label.split(' ').first,
                                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                if (snap.hasError)
                  const Text('Could not load your review queue.', style: TextStyle(color: AppColors.red)),
              ],
            );
          },
        ),
      ),
    );
  }
}
