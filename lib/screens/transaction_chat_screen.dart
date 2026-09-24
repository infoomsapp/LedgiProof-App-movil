import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/transaction_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

/// Chat scoped to ONE transaction -- what a bookkeeper opens to ask "what
/// was this?" on a specific line, and what a client sees as a single thread
/// under that transaction. This is the mobile side of the same
/// transaction_messages system the web's per-transaction chat panel uses
/// (useTransactionChat.ts / chat-tx.service.ts), reachable here from the
/// Review tab so a transaction needing a decision can also be asked about.
class TransactionChatScreen extends StatefulWidget {
  final String transactionId;
  final String transactionLabel;

  const TransactionChatScreen({
    super.key,
    required this.transactionId,
    required this.transactionLabel,
  });

  @override
  State<TransactionChatScreen> createState() => _TransactionChatScreenState();
}

class _TransactionChatScreenState extends State<TransactionChatScreen> {
  final _service = TransactionChatService();
  final _controller = TextEditingController();
  String? get _myUserId => Supabase.instance.client.auth.currentUser?.id;

  String? _conversationId;
  Future<TransactionMessagesResponse>? _future;
  bool _sending = false;
  bool _opening = true;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final convId = await _service.openOrGetConversation(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _conversationId = convId;
        _future = _load(convId);
        _opening = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _openError = friendlyError(e);
      });
    }
  }

  Future<TransactionMessagesResponse> _load(String conversationId) async {
    final res = await _service.getMessages(conversationId);
    unawaited(_service.markRead(conversationId).catchError((_) {}));
    return res;
  }

  void _reload() {
    final convId = _conversationId;
    if (convId == null) return;
    setState(() { _future = _load(convId); });
  }

  Future<void> _send() async {
    final convId = _conversationId;
    final text = _controller.text.trim();
    if (convId == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(conversationId: convId, body: text);
      _controller.clear();
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transactionLabel,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _opening
          ? const Center(child: CircularProgressIndicator())
          : _openError != null
              ? Center(
                  child: Text('Could not open chat.',
                      style: TextStyle(color: AppColors.inkMuted)),
                )
              : Column(
                  children: [
                    Expanded(
                      child: FutureBuilder<TransactionMessagesResponse>(
                        future: _future,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return Center(
                              child: Text('Could not load messages.',
                                  style: TextStyle(color: AppColors.inkMuted)),
                            );
                          }
                          final messages = snap.data?.messages ?? [];
                          if (messages.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'Ask a question about this transaction.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: messages.length,
                            itemBuilder: (context, i) {
                              final m = messages[messages.length - 1 - i];
                              final isMine = m.senderId != null && m.senderId == _myUserId;
                              return _Bubble(message: m, isMine: isMine);
                            },
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          border: Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                minLines: 1,
                                maxLines: 4,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Ask about this transaction…',
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _sending ? null : _send,
                              icon: _sending
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: AppColors.primary),
                                    )
                                  : Icon(Icons.send, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final TransactionMessage message;
  final bool isMine;
  const _Bubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isMine ? AppColors.primary : AppColors.surface;
    final fg = isMine ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMine && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4),
              child: Text(message.senderName!,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSubtle)),
            ),
          Container(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              border: isMine ? null : Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(message.body ?? '',
                style: TextStyle(fontSize: 13.5, color: fg, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
