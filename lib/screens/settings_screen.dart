import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show themeController;
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lp_logo.dart';

/// Settings: appearance, who you are signed in as, and which workspace this
/// session is pointed at.
class SettingsScreen extends StatefulWidget {
  final Workspace workspace;
  const SettingsScreen({super.key, required this.workspace});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '—';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: LpLogo(height: 84)),
          const SizedBox(height: 24),
          _SectionLabel('Appearance'),
          _Card(
            child: Column(
              children: [
                _ThemeOption(
                  icon: Icons.brightness_auto_outlined,
                  label: 'Match my phone',
                  mode: LpThemeMode.system,
                  onPick: _pick,
                ),
                _Divider(),
                _ThemeOption(
                  icon: Icons.light_mode_outlined,
                  label: 'Light',
                  mode: LpThemeMode.light,
                  onPick: _pick,
                ),
                _Divider(),
                _ThemeOption(
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark',
                  mode: LpThemeMode.dark,
                  onPick: _pick,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Account'),
          _Card(
            child: Column(
              children: [
                _InfoRow(icon: Icons.mail_outline, label: 'Signed in as', value: email),
                _Divider(),
                _InfoRow(
                    icon: Icons.apartment_outlined,
                    label: 'Workspace',
                    value: widget.workspace.orgName),
                _Divider(),
                _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Your role',
                    value: widget.workspace.role),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Supabase.instance.client.auth.signOut(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.red),
                    const SizedBox(width: 12),
                    Text('Sign out',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.red)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(LpThemeMode mode) async {
    await themeController.setMode(mode);
    if (mounted) setState(() {});
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final LpThemeMode mode;
  final Future<void> Function(LpThemeMode) onPick;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.mode,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final selected = themeController.mode == mode;
    return InkWell(
      onTap: () => onPick(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.inkMuted),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.ink,
                )),
            const Spacer(),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.inkSubtle,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: AppColors.border);
}
