import 'package:flutter/material.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// Firm / Personal switching, ported from the web app's OrgSelector.
///
/// The shape of this follows what QuickBooks Online Accountant and Xero both
/// settled on: an accountant's own books are a separate workspace from the
/// firm's and from each client's, and the way in is a single control in the
/// header rather than a setting buried in a menu. The switch only exists for
/// firm-side roles; a client-portal user or a plain solo user never sees it.
class WorkspaceSwitcher extends StatelessWidget {
  final WorkspaceScope scope;
  final Future<void> Function(Workspace) onSwitch;
  final Future<void> Function() onCreatePersonal;

  const WorkspaceSwitcher({
    super.key,
    required this.scope,
    required this.onSwitch,
    required this.onCreatePersonal,
  });

  static IconData iconFor(OrgCategory c) => switch (c) {
        OrgCategory.personal => Icons.person_outline,
        OrgCategory.firm => Icons.apartment_outlined,
        OrgCategory.clientCompany => Icons.work_outline,
        OrgCategory.unknown => Icons.folder_outlined,
      };

  static Color colorFor(OrgCategory c) => switch (c) {
        OrgCategory.personal => AppColors.cyan,
        OrgCategory.firm => AppColors.primary,
        OrgCategory.clientCompany => AppColors.green,
        OrgCategory.unknown => AppColors.inkMuted,
      };

  @override
  Widget build(BuildContext context) {
    final active = scope.active;

    // Not eligible: show the name as plain text, exactly as before.
    if (!scope.canToggle) {
      return Text(
        active.orgName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(active.category),
                size: 16, color: colorFor(active.category)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                active.orgName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more, size: 17, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _SwitcherSheet(
        scope: scope,
        onSwitch: onSwitch,
        onCreatePersonal: onCreatePersonal,
      ),
    );
  }
}

class _SwitcherSheet extends StatelessWidget {
  final WorkspaceScope scope;
  final Future<void> Function(Workspace) onSwitch;
  final Future<void> Function() onCreatePersonal;

  const _SwitcherSheet({
    required this.scope,
    required this.onSwitch,
    required this.onCreatePersonal,
  });

  @override
  Widget build(BuildContext context) {
    final firstFirm = scope.firmOrgs.isEmpty ? null : scope.firmOrgs.first;
    final firstPersonal =
        scope.personalOrgs.isEmpty ? null : scope.personalOrgs.first;
    final activeCat = scope.active.category;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workspace',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Text(
                    'Your firm’s books and your own are kept separate.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),

            // One-tap Firm / Personal pill, the same two-sided control the web
            // uses. The Personal side becomes a create action when there is no
            // personal workspace yet, rather than silently doing nothing.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeButton(
                        icon: Icons.person_outline,
                        label: scope.hasPersonal ? 'Personal' : 'Personal +',
                        selected: activeCat == OrgCategory.personal,
                        onTap: () async {
                          Navigator.of(context).pop();
                          if (firstPersonal != null) {
                            await onSwitch(firstPersonal);
                          } else {
                            await onCreatePersonal();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ModeButton(
                        icon: Icons.apartment_outlined,
                        label: 'Firm',
                        selected: activeCat == OrgCategory.firm,
                        onTap: firstFirm == null
                            ? null
                            : () async {
                                Navigator.of(context).pop();
                                await onSwitch(firstFirm);
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),
            if (scope.firmOrgs.isNotEmpty)
              _Group(
                  title: 'Firm',
                  orgs: scope.firmOrgs,
                  scope: scope,
                  onSwitch: onSwitch),
            if (scope.personalOrgs.isNotEmpty)
              _Group(
                  title: 'Personal',
                  orgs: scope.personalOrgs,
                  scope: scope,
                  onSwitch: onSwitch),
            if (scope.clientOrgs.isNotEmpty)
              _Group(
                  title: 'Clients',
                  orgs: scope.clientOrgs,
                  scope: scope,
                  onSwitch: onSwitch),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Workspace> orgs;
  final WorkspaceScope scope;
  final Future<void> Function(Workspace) onSwitch;

  const _Group({
    required this.title,
    required this.orgs,
    required this.scope,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.inkSubtle,
            ),
          ),
        ),
        ...orgs.map((o) {
          final isActive = o.orgId == scope.active.orgId;
          return InkWell(
            onTap: isActive
                ? null
                : () async {
                    Navigator.of(context).pop();
                    await onSwitch(o);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(WorkspaceSwitcher.iconFor(o.category),
                      size: 18, color: WorkspaceSwitcher.colorFor(o.category)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.orgName,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight:
                                    isActive ? FontWeight.w700 : FontWeight.w500,
                                color: AppColors.ink)),
                        const SizedBox(height: 2),
                        Text(o.roleLabel,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSubtle)),
                      ],
                    ),
                  ),
                  if (isActive)
                    Icon(Icons.check_circle,
                        size: 18, color: AppColors.primary),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.inkMuted;
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
