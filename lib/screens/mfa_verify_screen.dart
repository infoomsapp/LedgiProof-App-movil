import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/lp_logo.dart';

/// Second step of sign-in for a user with a verified TOTP factor -- the phone
/// counterpart of the web's MfaVerify page.
///
/// AuthGate (main.dart) shows this whenever the session is still aal1 but the
/// user could reach aal2. The database rejects aal1 requests from such a user
/// (see supabase/sql/security_mfa_enforcement.sql in the web repo), so there
/// is nothing useful to show before this step anyway. On success the auth
/// stream emits mfaChallengeVerified and AuthGate swaps to the app by itself.
class MfaVerifyScreen extends StatefulWidget {
  const MfaVerifyScreen({super.key});

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final mfa = Supabase.instance.client.auth.mfa;
    try {
      final factors = await mfa.listFactors();
      final verified = factors.totp.where((f) => f.status == FactorStatus.verified);
      if (verified.isEmpty) {
        setState(() => _error = 'No authenticator is set up for this account.');
        return;
      }
      await mfa.challengeAndVerify(factorId: verified.first.id, code: code);
    } on AuthException {
      setState(() => _error = 'Invalid code. Try again.');
    } catch (_) {
      setState(() => _error = 'Could not verify the code. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: LpLogo(height: 96)),
              const SizedBox(height: 24),
              Text(
                'Two-factor verification',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the 6-digit code from your authenticator app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _codeCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.ink, fontSize: 22, letterSpacing: 8),
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12.5)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Verify'),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => Supabase.instance.client.auth.signOut(),
                  child: const Text('Use a different account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
