import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/lp_brand_footer.dart';
import '../widgets/lp_logo.dart';
import 'accept_invite_screen.dart';

/// "email" or "LedgiProof ID" (LP-7018786, or just the digits) -- the way
/// Intuit's sign-in takes "email or user ID".
bool isEmailLogin(String value) => value.contains('@');

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Same idea as the web's "Remember me" (src/lib/authStorage.ts): only the
  // email or ID is kept on this phone, never the password.
  static const _rememberKey = 'lp-remember-login';
  static const _loginKey = 'lp-remembered-login';

  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  bool _remember = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberKey) ?? true;
      final saved = prefs.getString(_loginKey);
      if (!mounted) return;
      setState(() => _remember = remember);
      if (remember && saved != null && _loginCtrl.text.isEmpty) _loginCtrl.text = saved;
    } catch (_) {
      // Nothing saved is fine: the field just starts empty.
    }
  }

  Future<void> _saveLogin(String login) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _remember);
      if (_remember) {
        await prefs.setString(_loginKey, login);
      } else {
        await prefs.remove(_loginKey);
      }
    } catch (_) {/* best effort */}
  }

  Future<void> _signIn() async {
    final login = _loginCtrl.text.trim();
    if (login.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Enter your email or user ID and your password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (isEmailLogin(login)) {
        await auth.signInWithPassword(email: login, password: _passwordCtrl.text);
      } else {
        // The ID becomes the account's email on the server (sign-in-id);
        // the app only receives the session.
        final res = await Supabase.instance.client.functions.invoke('sign-in-id', body: {
          'user_id': login,
          'password': _passwordCtrl.text,
        });
        final data = res.data as Map<String, dynamic>;
        await auth.setSession(data['refresh_token'] as String, accessToken: data['access_token'] as String?);
      }
      await _saveLogin(login);
      // AuthGate (main.dart) listens to the auth state stream and swaps
      // to AppShell on its own -- no manual navigation needed here.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on FunctionException catch (e) {
      final details = e.details;
      setState(() => _error = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Could not sign in. Try again.');
    } catch (_) {
      setState(() => _error = 'Could not sign in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The real lockup, not a gradient-masked text imitation of it.
                      const Center(child: LpLogo(height: 132)),
                      const SizedBox(height: 6),
                      Text(
                        'Smart bookkeeping that learns from you',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 36),
                      TextField(
                        controller: _loginCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email, AutofillHints.username],
                        style: TextStyle(color: AppColors.ink),
                        decoration: const InputDecoration(
                          labelText: 'Email or user ID',
                          helperText: 'Your user ID is on your profile (LP-1234567)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: !_passwordVisible,
                        autofillHints: const [AutofillHints.password],
                        style: TextStyle(color: AppColors.ink),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _passwordVisible = !_passwordVisible),
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.inkMuted,
                            ),
                            tooltip:
                                _passwordVisible ? 'Hide password' : 'Show password',
                          ),
                        ),
                        onSubmitted: (_) => _signIn(),
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v ?? true),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('Remember my email or user ID',
                            style: TextStyle(fontSize: 13, color: AppColors.ink)),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 4),
                        Text(_error!, style: TextStyle(color: AppColors.red, fontSize: 12.5)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _signIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 16),
                      // Real gap fixed 2026-09-24: the app had no way at all to
                      // redeem a client-portal invite from the phone -- a client
                      // who received one on their email had to go find a computer.
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AcceptInviteScreen()),
                          ),
                          child: const Text('Have an invitation? Accept it here'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const LpBrandFooter(),
          ],
        ),
      ),
    );
  }
}
