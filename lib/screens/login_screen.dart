import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // AuthGate (main.dart) listens to the auth state stream and swaps
      // to AppShell on its own -- no manual navigation needed here.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not sign in. Check your connection and try again.');
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
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                ).createShader(bounds),
                child: const Text(
                  'LedgiProof',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Smart bookkeeping that learns from you',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.ink),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                style: const TextStyle(color: AppColors.ink),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
              ],
              const SizedBox(height: 20),
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
            ],
          ),
        ),
      ),
    );
  }
}
