import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class _MoreItem {
  final IconData icon;
  final String label;
  final bool destructive;
  const _MoreItem(this.icon, this.label, {this.destructive = false});
}

const _items = [
  _MoreItem(Icons.checklist_outlined, 'Checklists'),
  _MoreItem(Icons.schedule_outlined, 'Time'),
  _MoreItem(Icons.link_outlined, 'Connections'),
  _MoreItem(Icons.settings_outlined, 'Settings'),
];

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ..._items.map((item) => _MoreRow(
                item: item,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.label} — coming in the next build pass')),
                ),
              )),
          const SizedBox(height: 8),
          _MoreRow(
            item: const _MoreItem(Icons.logout, 'Sign out', destructive: true),
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final _MoreItem item;
  final VoidCallback onTap;
  const _MoreRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = item.destructive ? AppColors.red : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: item.destructive ? AppColors.red : AppColors.inkMuted),
              const SizedBox(width: 12),
              Text(item.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: color)),
              const Spacer(),
              if (!item.destructive) const Icon(Icons.chevron_right, size: 16, color: AppColors.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
