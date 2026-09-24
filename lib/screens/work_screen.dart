import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/client_action_sheet.dart';

/// Same tab slot, different content by role: an own-invoices list for a
/// solo/PYME workspace, a client list for a bookkeeping/accountant firm --
/// decided here by organizations.is_firm, matching the mobile UX design.
class WorkScreen extends StatefulWidget {
  final Workspace workspace;
  const WorkScreen({super.key, required this.workspace});

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  final _books = BooksService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workspace.isFirm ? 'Clients' : 'Invoices',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: widget.workspace.isFirm ? _ClientsList(books: _books, workspace: widget.workspace)
                                     : _InvoicesList(books: _books, orgId: widget.workspace.orgId),
    );
  }
}

class _InvoicesList extends StatelessWidget {
  final BooksService books;
  final String orgId;
  const _InvoicesList({required this.books, required this.orgId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InvoiceSummary>>(
      future: books.getInvoices(orgId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(child: Text('No invoices yet', style: TextStyle(color: AppColors.inkMuted)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final inv = items[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('#${inv.invoiceNumber}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                        const SizedBox(height: 2),
                        Text(inv.status, style: TextStyle(fontSize: 11, color: AppColors.inkSubtle)),
                      ],
                    ),
                  ),
                  Text('\$${inv.total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ClientsList extends StatelessWidget {
  final BooksService books;
  final Workspace workspace;
  const _ClientsList({required this.books, required this.workspace});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClientSummary>>(
      future: books.getClients(workspace.orgId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(child: Text('No clients yet', style: TextStyle(color: AppColors.inkMuted)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final c = items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showClientActionSheet(context,
                  workspace: workspace, client: c),
              child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.blueBg,
                    child: Text(c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
                        style: TextStyle(color: AppColors.primaryInk, fontWeight: FontWeight.w700, fontSize: 13)),
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
                  Icon(Icons.chevron_right, color: AppColors.inkSubtle, size: 18),
                ],
              ),
              ),
            );
          },
        );
      },
    );
  }
}
