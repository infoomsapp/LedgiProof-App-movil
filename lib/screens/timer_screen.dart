import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/time_entry_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

class TimerScreen extends StatefulWidget {
  final Workspace workspace;
  const TimerScreen({super.key, required this.workspace});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final _service = TimeEntryService();
  final _descriptionCtrl = TextEditingController();

  TimeEntry? _running;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  bool _busy = false;
  bool _loadingExisting = true;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final running = await _service.getRunningTimer(widget.workspace.orgId, _userId);
      if (!mounted) return;
      setState(() {
        _running = running;
        _loadingExisting = false;
      });
      if (running?.startedAt != null) _startTicking(running!.startedAt!);
    } catch (_) {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  void _startTicking(DateTime startedAt) {
    _ticker?.cancel();
    _tick(startedAt);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick(startedAt));
  }

  void _tick(DateTime startedAt) {
    if (!mounted) return;
    setState(() => _elapsed = DateTime.now().toUtc().difference(startedAt));
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final entry = await _service.startTimer(
        orgId: widget.workspace.orgId,
        userId: _userId,
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
      );
      setState(() {
        _running = entry;
        _elapsed = Duration.zero;
      });
      _startTicking(entry.startedAt!);
    } catch (e) {
      _showError('Could not start the timer.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final running = _running;
    if (running == null) return;
    setState(() => _busy = true);
    try {
      final stopped = await _service.stopTimer(running.id);
      _ticker?.cancel();
      if (!mounted) return;
      setState(() {
        _running = null;
        _elapsed = Duration.zero;
        _descriptionCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved · ${stopped.durationMinutes} min')),
      );
    } catch (e) {
      _showError('Could not stop the timer.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _running != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Log time', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: 190, height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isRunning ? AppColors.primary : AppColors.border,
                        width: 3,
                        style: isRunning ? BorderStyle.solid : BorderStyle.solid,
                      ),
                      boxShadow: isRunning
                          ? [BoxShadow(color: AppColors.blueBg, blurRadius: 0, spreadRadius: 8)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        _fmt(_elapsed),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                          fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!isRunning)
                    TextField(
                      controller: _descriptionCtrl,
                      style: const TextStyle(color: AppColors.ink),
                      decoration: const InputDecoration(
                        labelText: 'What are you working on? (optional)',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    Text(
                      _running?.description?.isNotEmpty == true ? _running!.description! : 'Untitled entry',
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : (isRunning ? _stop : _start),
                      style: FilledButton.styleFrom(
                        backgroundColor: isRunning ? AppColors.red : AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isRunning ? 'Stop' : 'Start', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}
