import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/books_service.dart';
import '../services/mileage_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

enum _TrackerStage { checkingConnection, connectedElsewhere, idle, running, choosingPurpose, saving }

enum _Purpose { business, personal, client }

/// The basic in-app trip tracker from the mobile UX design: Start -> Stop ->
/// purpose, nothing else (no odometer photo, no fraud scoring -- that stays
/// ControlMiles-only). If the org already has an active ControlMiles
/// connection this screen never shows the tracker at all, per the design's
/// rule against ever offering two competing ways to log the same trip.
class TripTrackerScreen extends StatefulWidget {
  final Workspace workspace;
  const TripTrackerScreen({super.key, required this.workspace});

  @override
  State<TripTrackerScreen> createState() => _TripTrackerScreenState();
}

class _TripTrackerScreenState extends State<TripTrackerScreen> {
  final _mileage = MileageService();
  final _books = BooksService();

  _TrackerStage _stage = _TrackerStage.checkingConnection;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  double _meters = 0;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _clock;
  _Purpose _purpose = _Purpose.business;
  String? _clientId;
  String? _clientLabel;
  String? _error;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;
  double get _miles => _meters / 1609.344;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    try {
      final connected = await _mileage.hasActiveControlMilesConnection(widget.workspace.orgId);
      if (!mounted) return;
      setState(() => _stage = connected ? _TrackerStage.connectedElsewhere : _TrackerStage.idle);
    } catch (_) {
      if (mounted) setState(() => _stage = _TrackerStage.idle);
    }
  }

  Future<void> _start() async {
    setState(() => _error = null);

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _error = 'Location permission is required to log a trip.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = 'Turn on location services to log a trip.');
      return;
    }

    _meters = 0;
    _lastPosition = null;
    _startedAt = DateTime.now();
    setState(() => _stage = _TrackerStage.running);

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8),
    ).listen((pos) {
      if (_lastPosition != null) {
        final delta = Geolocator.distanceBetween(
          _lastPosition!.latitude, _lastPosition!.longitude,
          pos.latitude, pos.longitude,
        );
        // Ignore GPS jitter while stationary -- a few meters of noise
        // shouldn't accumulate into fake distance over a long stop.
        if (delta > 3) _meters += delta;
      }
      _lastPosition = pos;
      if (mounted) setState(() {});
    });
  }

  Future<void> _stop() async {
    _clock?.cancel();
    await _positionSub?.cancel();
    setState(() => _stage = _TrackerStage.choosingPurpose);
  }

  Future<void> _pickClient() async {
    try {
      final clients = await _books.getClients(widget.workspace.orgId);
      if (!mounted) return;
      final selected = await showModalBottomSheet<ClientSummary>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => ListView(
          shrinkWrap: true,
          children: clients
              .map((c) => ListTile(
                    title: Text(c.displayName, style: const TextStyle(color: AppColors.ink)),
                    onTap: () => Navigator.pop(ctx, c),
                  ))
              .toList(),
        ),
      );
      if (selected != null) {
        setState(() {
          _purpose = _Purpose.client;
          _clientId = selected.id;
          _clientLabel = selected.displayName;
        });
      }
    } catch (_) {
      setState(() => _error = 'Could not load your clients.');
    }
  }

  Future<void> _confirmPurpose() async {
    if (_purpose == _Purpose.personal) {
      // mileage_entries is a deduction table, not a trip log -- a personal
      // drive has no business deduction, so there's nothing honest to save
      // here (matches the web app: addMileageEntry always writes
      // category: 'business', there's no personal-mileage path today).
      _reset();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Personal trips aren't saved — only business mileage affects your deduction.")),
      );
      return;
    }

    setState(() => _stage = _TrackerStage.saving);
    try {
      await _mileage.addMileageEntry(
        orgId: widget.workspace.orgId,
        userId: _userId,
        miles: double.parse(_miles.toStringAsFixed(1)),
        date: DateTime.now().toIso8601String().substring(0, 10),
        purpose: _purpose == _Purpose.client && _clientLabel != null ? 'Client: $_clientLabel' : null,
        clientId: _clientId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved · ${_miles.toStringAsFixed(1)} mi')),
      );
      _reset();
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _TrackerStage.choosingPurpose);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save the trip. Check you're an owner, admin, or accountant on this workspace.")),
      );
    }
  }

  void _reset() {
    setState(() {
      _stage = _TrackerStage.idle;
      _meters = 0;
      _elapsed = Duration.zero;
      _purpose = _Purpose.business;
      _clientId = null;
      _clientLabel = null;
    });
  }

  String _fmtClock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _clock?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log a trip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: switch (_stage) {
        _TrackerStage.checkingConnection => const Center(child: CircularProgressIndicator()),
        _TrackerStage.connectedElsewhere => _buildConnectedBanner(),
        _TrackerStage.idle => _buildIdle(),
        _TrackerStage.running => _buildRunning(),
        _TrackerStage.choosingPurpose => _buildPurpose(),
        _TrackerStage.saving => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildConnectedBanner() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link, color: AppColors.accent, size: 28),
              const SizedBox(height: 12),
              const Text('Trips sync automatically', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              const Text(
                'Your ControlMiles account is connected. Every closed trip lands here on its own — nothing to start or stop from this app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 180, height: 180,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 2, style: BorderStyle.solid)),
            child: const Center(child: Icon(Icons.navigation_outlined, color: AppColors.inkSubtle, size: 40)),
          ),
          const SizedBox(height: 16),
          const Text('Tap start when you leave', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5), textAlign: TextAlign.center),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.play_arrow, size: 20), SizedBox(width: 6), Text('Start', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunning() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 190, height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 3),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_fmtClock(_elapsed), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text('${_miles.toStringAsFixed(1)} mi', style: const TextStyle(fontSize: 12, color: AppColors.inkSubtle)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Safe to lock your phone', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _stop,
              style: FilledButton.styleFrom(backgroundColor: AppColors.red, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Stop', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurpose() {
    final rate = businessMileageRateForDate(DateTime.now().toIso8601String().substring(0, 10));
    final estimate = _miles * rate;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.check_circle_outline, color: AppColors.green, size: 36),
          const SizedBox(height: 10),
          Text('${_miles.toStringAsFixed(1)} mi · \$${estimate.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.green)),
          const SizedBox(height: 24),
          const Align(alignment: Alignment.centerLeft, child: Text('What was this for?', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5))),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _purposeChip('Business', _Purpose.business)),
              const SizedBox(width: 8),
              Expanded(child: _purposeChip('Personal', _Purpose.personal)),
              const SizedBox(width: 8),
              Expanded(child: _purposeChip(_clientLabel ?? 'Client', _Purpose.client, onTap: _pickClient)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _confirmPurpose,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_purpose == _Purpose.personal ? 'Discard trip' : 'Save trip', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _purposeChip(String label, _Purpose value, {VoidCallback? onTap}) {
    final selected = _purpose == value;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap ?? () => setState(() => _purpose = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueBg : AppColors.surface,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? AppColors.primaryInk : AppColors.inkMuted)),
      ),
    );
  }
}
