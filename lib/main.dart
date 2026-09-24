import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'services/workspace_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  runApp(const LedgiProofApp());
}

class LedgiProofApp extends StatelessWidget {
  const LedgiProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LedgiProof',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// Swaps between the login screen and the app shell based on Supabase's own
/// auth session -- the same session token the web app would issue, since
/// both point at the same project.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snap) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return const _WorkspaceLoader();
      },
    );
  }
}

class _WorkspaceLoader extends StatefulWidget {
  const _WorkspaceLoader();

  @override
  State<_WorkspaceLoader> createState() => _WorkspaceLoaderState();
}

class _WorkspaceLoaderState extends State<_WorkspaceLoader> {
  late Future<Workspace?> _workspace;

  @override
  void initState() {
    super.initState();
    _workspace = WorkspaceService().loadActiveWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Workspace?>(
      future: _workspace,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || snap.data == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.red, size: 32),
                    const SizedBox(height: 12),
                    const Text('Could not load your workspace.', style: TextStyle(color: AppColors.ink)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return AppShell(workspace: snap.data!);
      },
    );
  }
}
