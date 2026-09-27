import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/lp_logo.dart';

/// LedgiProof has no free plan: every plan starts with a free trial and then
/// one must be chosen (the web's ChoosePlan screen). This shows [child] while
/// the workspace's trial is running or its plan is paid, and a "trial ended"
/// screen once get_org_access() says 'expired'.
///
/// Plans are chosen on the web, not in the app -- the screen says so without
/// linking to a purchase. Portal clients are never gated (the firm pays).
/// Fails open on a network error: the database already zeroes an expired
/// workspace's quota, this screen is the friendly explanation.
class TrialEndedGate extends StatefulWidget {
  final String orgId;
  final bool isPortalClient;
  final bool canSwitch;
  final VoidCallback onSwitchWorkspace;
  final Widget child;

  const TrialEndedGate({
    super.key,
    required this.orgId,
    required this.isPortalClient,
    required this.canSwitch,
    required this.onSwitchWorkspace,
    required this.child,
  });

  @override
  State<TrialEndedGate> createState() => _TrialEndedGateState();
}

class _TrialEndedGateState extends State<TrialEndedGate> {
  bool _checking = true;
  bool _expired = false;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (widget.isPortalClient) {
      setState(() => _checking = false);
      return;
    }
    setState(() => _checking = true);
    try {
      final res = await Supabase.instance.client
          .rpc('get_org_access', params: {'p_org_id': widget.orgId});
      final data = res as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _expired = data['state'] == 'expired';
        _isOwner = data['is_owner'] == true;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _expired = false;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_expired) return widget.child;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: LpLogo(height: 96)),
              const SizedBox(height: 20),
              // The four semaphore states -- the product's mark.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const ['blue', 'green', 'amber', 'red']
                    .map((k) => semaphoreColors[k]!)
                    .map((c) => Container(
                          width: 9, height: 9,
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Text(
                _isOwner ? 'Your free trial has ended' : 'This workspace needs an active plan',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _isOwner
                    ? 'Choose a plan from the LedgiProof website to keep working. Everything you entered is saved.'
                    : 'Ask the workspace owner to choose a plan. Your work is saved.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _check,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Already subscribed? Check again'),
              ),
              if (widget.canSwitch) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onSwitchWorkspace,
                  child: const Text('Switch workspace'),
                ),
              ],
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: Text('Sign out', style: TextStyle(color: AppColors.inkMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
