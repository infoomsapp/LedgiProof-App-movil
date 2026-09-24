import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet to pick which client an action (scan receipt, etc.) belongs
/// to, in a firm workspace. Returns the chosen ClientSummary, or null if
/// dismissed. Mirrors how bank connections already scope firm-mode actions
/// per client -- receipt capture follows the same product rule.
Future<ClientSummary?> pickClient(BuildContext context, {required String orgId}) {
  final books = BooksService();
  return showModalBottomSheet<ClientSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => FutureBuilder<List<ClientSummary>>(
        future: books.getClients(orgId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final clients = snap.data ?? [];
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(100)),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Which client is this for?',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: clients.isEmpty
                    ? Center(child: Text('No clients yet', style: TextStyle(color: AppColors.inkMuted)))
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: clients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final c = clients[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.of(ctx).pop(c),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: AppColors.blueBg,
                                    child: Text(
                                      c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
                                      style: TextStyle(color: AppColors.primaryInk, fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.displayName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                                        if (c.companyName != null)
                                          Text(c.companyName!, style: TextStyle(fontSize: 11, color: AppColors.inkSubtle)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
