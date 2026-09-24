import 'package:flutter/material.dart';
import '../services/accountant_invite_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

/// What a personal ("started") workspace gets instead of Chat: there is no
/// client relationship here for chat to be scoped to, and no way for a solo
/// user to self-grant org membership to anyone. This asks -- it emails a
/// named accountant a link to set the person up as a client the real way,
/// on the web, from the accountant's own side.
class AddAccountantScreen extends StatefulWidget {
  final Workspace workspace;
  const AddAccountantScreen({super.key, required this.workspace});

  @override
  State<AddAccountantScreen> createState() => _AddAccountantScreenState();
}

class _AddAccountantScreenState extends State<AddAccountantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _service = AccountantInviteService();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.requestAccountant(
        orgId: widget.workspace.orgId,
        accountantEmail: _emailController.text.trim(),
        accountantName: _nameController.text,
        note: _noteController.text,
      );
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send the request: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add an accountant',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _sent ? _SuccessView(email: _emailController.text.trim()) : _form(),
    );
  }

  Widget _form() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Know an accountant you want managing these books? We\'ll email '
              'them a link to set up their firm on LedgiProof and add you as '
              'a client -- the same way any firm adds a client here.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Accountant\'s email'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Required';
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Their name (optional)',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'A note for them (optional)',
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Send request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String email;
  const _SuccessView({required this.email});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, size: 34, color: AppColors.green),
            const SizedBox(height: 14),
            Text('Request sent',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              'We emailed $email a link to set up their firm and add you as a '
              'client. Once they do, this workspace will get a Chat tab here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
