import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/document_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

const Map<String, IconData> _kindIcon = {
  'attachment': Icons.attach_file,
  'receipt': Icons.receipt_long_outlined,
  'invoice': Icons.description_outlined,
  'statement': Icons.description_outlined,
  'tax_form': Icons.article_outlined,
  'contract': Icons.gavel_outlined,
  'other': Icons.folder_outlined,
};

/// Lists documents for a workspace (or one client within a firm workspace).
/// A photo/image opens in-app (full-screen, pinch-zoom) -- receipts and
/// invoices are evidence, and punting them out to a separate viewer was
/// exactly the complaint this screen exists to fix. A PDF still opens
/// externally, which is fine (same split the web side just adopted).
class DocumentsScreen extends StatefulWidget {
  final String orgId;
  final String? clientId;
  final String title;
  const DocumentsScreen({super.key, required this.orgId, this.clientId, this.title = 'Documents'});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _service = DocumentService();
  late Future<List<DocumentRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.list(orgId: widget.orgId, clientId: widget.clientId);
  }

  void _reload() {
    setState(() { _future = _service.list(orgId: widget.orgId, clientId: widget.clientId); });
  }

  Future<void> _open(DocumentRow doc) async {
    try {
      final signed = await _service.getSignedUrl(doc.id);
      if (!mounted) return;
      if (signed.mimeType.startsWith('image/')) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _ImageViewerScreen(url: signed.url, filename: signed.filename),
        ));
      } else {
        final uri = Uri.parse(signed.url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () async { _reload(); await _future; },
        child: FutureBuilder<List<DocumentRow>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Icon(Icons.error_outline, color: AppColors.red, size: 32),
                const SizedBox(height: 10),
                Center(child: Text('Could not load documents.', style: TextStyle(color: AppColors.inkMuted))),
              ]);
            }
            final docs = snap.data ?? [];
            if (docs.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 80),
                Icon(Icons.folder_outlined, color: AppColors.inkSubtle, size: 32),
                const SizedBox(height: 10),
                Center(child: Text('No documents yet', style: TextStyle(color: AppColors.inkMuted))),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = docs[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _open(d),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(_kindIcon[d.documentKind] ?? Icons.folder_outlined, size: 18, color: AppColors.inkMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.filename,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                              const SizedBox(height: 2),
                              Text(
                                '${_formatBytes(d.sizeBytes)} · ${d.uploadedByRole == 'client' ? 'Client' : 'You'}',
                                style: TextStyle(fontSize: 11, color: AppColors.inkSubtle),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: AppColors.inkSubtle),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _ImageViewerScreen extends StatelessWidget {
  final String url;
  final String filename;
  const _ImageViewerScreen({required this.url, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(filename, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.network(
            url,
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load image.', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator(color: Colors.white);
            },
          ),
        ),
      ),
    );
  }
}
