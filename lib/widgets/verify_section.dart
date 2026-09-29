import 'package:flutter/material.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';
import '../utils/doc_format.dart';
import '../utils/errors.dart';

/// "Ready to verify" -- the green half of the semaphore, same as the web's
/// src/components/review/VerifyQueue.tsx. LedgiProof already put these in the
/// books by itself (a rule, a merchant confirmed three times, an exact match);
/// a person verifies them (blue) or changes the category (back to For review,
/// and the merchant goes back to "ask me"). Hidden when there is nothing.
class VerifySection extends StatefulWidget {
  final String orgId;
  final String? clientId;
  final bool canWrite;

  /// Bump to reload (pull-to-refresh, scope change).
  final int refreshToken;

  /// A category was removed: the For review list has a new row.
  final VoidCallback? onChanged;

  const VerifySection({
    super.key,
    required this.orgId,
    required this.clientId,
    required this.canWrite,
    this.refreshToken = 0,
    this.onChanged,
  });

  @override
  State<VerifySection> createState() => _VerifySectionState();
}

class _VerifySectionState extends State<VerifySection> {
  final _service = ReviewService();
  List<VerificationItem> _items = [];
  String? _busy;
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VerifySection old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken || old.clientId != widget.clientId || old.orgId != widget.orgId) {
      _load();
    }
  }

  Future<void> _load() async {
    final clientId = widget.clientId;
    try {
      final items = await _service.getVerificationQueue(widget.orgId, clientId);
      if (!mounted || clientId != widget.clientId) return;
      setState(() => _items = items);
    } catch (_) {
      // The inbox still works without this section; it just stays hidden.
      if (mounted) setState(() => _items = []);
    }
  }

  Future<void> _run(VerificationItem it, Future<void> Function() fn, {bool changed = false}) async {
    setState(() {
      _busy = it.id;
      _errors.remove(it.id);
    });
    try {
      await fn();
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => x.id == it.id));
      if (changed) widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _errors[it.id] = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('Ready to verify · ${_items.length}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'LedgiProof put these in the books by itself: a rule, a merchant you confirmed three times, or an exact match. Verify them, or change the category.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
            ),
          ),
          for (final it in _items) ...[_row(it), const SizedBox(height: 8)],
        ],
      ),
    );
  }

  Widget _row(VerificationItem it) {
    final busy = _busy == it.id;
    final flagged = it.semaphore == 'amber' || it.semaphore == 'red';
    final what = it.matchedTo != null ? 'Settles ${it.matchedTo}' : (it.categoryName ?? '—');
    final how = [
      if (it.auto) 'Automatic',
      suggestionSourceLabel(it.source),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Opacity(
      opacity: busy ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: flagged ? AppColors.amber : AppColors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('${it.date} · $what${how.isEmpty ? '' : ' · $how'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                Text(formatMoney(it.amount, currency: it.currency),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: it.amount > 0 ? AppColors.green : AppColors.ink)),
              ],
            ),
            if (_errors[it.id] != null) ...[
              const SizedBox(height: 6),
              Text(_errors[it.id]!, style: TextStyle(fontSize: 11.5, color: AppColors.red)),
            ],
            if (widget.canWrite) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (it.matchedTo == null)
                    TextButton(
                      onPressed: busy ? null : () => _run(it, () => _service.uncategorize(widget.orgId, it.id), changed: true),
                      child: const Text('Change'),
                    ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: busy ? null : () => _run(it, () => _service.verify(widget.orgId, it.id)),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Verify'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
