import 'package:flutter/material.dart';
import '../services/client_portal_auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/errors.dart';

/// Accepts a client-portal invite token on the phone -- the missing piece
/// the user flagged directly: the app had a Sign In screen and nothing
/// else, so a client invited from the web had no way to actually redeem
/// that invite from mobile, and an account created any other way came out
/// as a firm instead of a portal client under the firm that invited them.
///
/// Two stages: paste the token/link and look it up, then either create a
/// new account (name + password) or sign in with an existing one --
/// mirrors ClientPortalActivatePage.tsx's own "already have an account?"
/// split, since an invited email can easily already exist (confirmed live
/// on web this same session).
class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key});

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

enum _Stage { enterToken, lookingUp, showInvite }

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _service = ClientPortalAuthService();
  final _tokenCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  _Stage _stage = _Stage.enterToken;
  InvitationPreview? _invite;
  String? _token;
  String? _error;
  bool _isNewAccount = true;
  bool _submitting = false;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final raw = _tokenCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste your invite link or code first.');
      return;
    }
    final token = ClientPortalAuthService.extractToken(raw);
    setState(() {
      _stage = _Stage.lookingUp;
      _error = null;
    });
    try {
      final preview = await _service.preview(token);
      if (!preview.isUsable) {
        setState(() {
          _stage = _Stage.enterToken;
          _error = preview.status != 'pending'
              ? 'This invitation has already been ${preview.status}.'
              : 'This invitation has expired. Ask your accountant to send a new one.';
        });
        return;
      }
      setState(() {
        _invite = preview;
        _token = token;
        _stage = _Stage.showInvite;
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.enterToken;
        _error = 'Invitation not found or already unavailable.';
      });
    }
  }

  Future<void> _submit() async {
    final invite = _invite;
    final token = _token;
    if (invite == null || token == null) return;
    if (_isNewAccount && _nameCtrl.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_isNewAccount) {
        await _service.signUpAndAccept(
          email: invite.email,
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
          token: token,
        );
      } else {
        await _service.signInAndAccept(
          email: invite.email,
          password: _passwordCtrl.text,
          token: token,
        );
      }
      // AuthGate (main.dart) listens to the auth state stream and swaps to
      // AppShell on its own once the session exists -- nothing to navigate
      // to here.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accept invitation',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _stage == _Stage.showInvite ? _buildInviteForm() : _buildTokenEntry(),
        ),
      ),
    );
  }

  Widget _buildTokenEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.mail_outline, size: 40, color: AppColors.inkSubtle),
        const SizedBox(height: 14),
        Text(
          'Paste the invite link or code from your accountant\'s email.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _tokenCtrl,
          maxLines: 3,
          minLines: 1,
          style: TextStyle(color: AppColors.ink),
          decoration: const InputDecoration(
            labelText: 'Invite link or code',
            hintText: 'https://app.ledgiproof.com/accept-client-portal/…',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12.5)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _stage == _Stage.lookingUp ? null : _lookUp,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _stage == _Stage.lookingUp
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Look up invitation'),
        ),
      ],
    );
  }

  Widget _buildInviteForm() {
    final invite = _invite!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.blueBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("You've been invited to",
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
              const SizedBox(height: 2),
              Text(invite.clientName,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryInk)),
              const SizedBox(height: 4),
              Text('by ${invite.orgName} · ${invite.roleLabel}',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // New account / existing account toggle
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: _ToggleTab(label: "I'm new here", selected: _isNewAccount, onTap: () => setState(() => _isNewAccount = true))),
              const SizedBox(width: 4),
              Expanded(child: _ToggleTab(label: 'I have an account', selected: !_isNewAccount, onTap: () => setState(() => _isNewAccount = false))),
            ],
          ),
        ),
        const SizedBox(height: 18),

        TextField(
          enabled: false,
          controller: TextEditingController(text: invite.email),
          style: TextStyle(color: AppColors.inkMuted),
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),

        if (_isNewAccount) ...[
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(labelText: 'Your full name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
        ],

        TextField(
          controller: _passwordCtrl,
          obscureText: !_passwordVisible,
          style: TextStyle(color: AppColors.ink),
          decoration: InputDecoration(
            labelText: _isNewAccount ? 'Create a password' : 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              icon: Icon(
                _passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20, color: AppColors.inkMuted,
              ),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12.5)),
        ],

        const SizedBox(height: 20),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isNewAccount ? 'Set password & continue' : 'Sign in & accept'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _stage = _Stage.enterToken;
            _invite = null;
            _token = null;
            _error = null;
          }),
          child: const Text('Use a different invitation'),
        ),
      ],
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
