import 'package:flutter/material.dart';
import '../services/books_service.dart';
import '../services/checklist_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';
import '../utils/checklist_logic.dart';
import '../utils/errors.dart';
import '../widgets/client_picker_sheet.dart';

enum ChecklistComposeMode { run, template }

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

/// Create a checklist without the web: either a one-off run to work through now,
/// or a recurring template that creates one on a schedule. Steps are typed one
/// per line (pasting a list works), or copied from an existing template.
class ChecklistComposeScreen extends StatefulWidget {
  final Workspace workspace;
  final ChecklistComposeMode mode;
  const ChecklistComposeScreen({super.key, required this.workspace, required this.mode});

  @override
  State<ChecklistComposeScreen> createState() => _ChecklistComposeScreenState();
}

class _ChecklistComposeScreenState extends State<ChecklistComposeScreen> {
  final _service = ChecklistService();
  final _title = TextEditingController();
  final _steps = TextEditingController();
  final _repeats = TextEditingController();

  ClientSummary? _client;
  DateTime _date = DateTime.now();
  DateTime? _endDate;
  ChecklistFrequency _frequency = ChecklistFrequency.monthly;
  bool _busy = false;
  String? _error;

  bool get _isTemplate => widget.mode == ChecklistComposeMode.template;

  @override
  void dispose() {
    _title.dispose();
    _steps.dispose();
    _repeats.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool end}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: end ? (_endDate ?? _date) : _date,
      firstDate: end ? _date : DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d == null) return;
    setState(() => end ? _endDate = d : _date = d);
  }

  Future<void> _pickClient() async {
    final c = await pickClient(context, orgId: widget.workspace.orgId);
    if (c != null && mounted) setState(() => _client = c);
  }

  /// Copies a template's steps into the box, so a one-off run can start from a
  /// schedule the firm already built.
  Future<void> _useTemplate() async {
    try {
      final templates = await _service.loadTemplates(widget.workspace.orgId);
      if (!mounted) return;
      if (templates.isEmpty) {
        setState(() => _error = 'There are no templates to copy yet.');
        return;
      }
      final picked = await showModalBottomSheet<RecurringChecklist>(
        context: context,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final t in templates)
                ListTile(
                  title: Text(t.title, style: TextStyle(color: AppColors.ink)),
                  subtitle: Text('${t.stepCount} steps · ${t.frequency.label}',
                      style: TextStyle(color: AppColors.inkSubtle)),
                  onTap: () => Navigator.of(ctx).pop(t),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      final steps = await _service.loadTemplateSteps(picked.id);
      if (!mounted) return;
      setState(() {
        _steps.text = steps.join('\n');
        if (_title.text.trim().isEmpty) _title.text = picked.title;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _save() async {
    final steps = parseSteps(_steps.text);
    final repeats = int.tryParse(_repeats.text.trim());
    final problem = validateChecklist(
      title: _title.text,
      steps: steps,
      isTemplate: _isTemplate,
      maxOccurrences: _repeats.text.trim().isEmpty ? null : (repeats ?? 0),
      start: _date,
      end: _endDate,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isTemplate) {
        await _service.createTemplate(
          orgId: widget.workspace.orgId,
          title: _title.text,
          frequency: _frequency,
          startDate: _date,
          steps: steps,
          clientId: _client?.id,
          endDate: _endDate,
          maxOccurrences: _repeats.text.trim().isEmpty ? null : repeats,
        );
      } else {
        await _service.createRun(
          orgId: widget.workspace.orgId,
          title: _title.text,
          runDate: _date,
          steps: steps,
          clientId: _client?.id,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = parseSteps(_steps.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isTemplate ? 'New template' : 'New checklist',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _isTemplate ? 'Template name' : 'Checklist name',
              hintText: _isTemplate ? 'Monthly close' : 'Onboard new client',
            ),
          ),
          const SizedBox(height: 12),
          if (widget.workspace.isFirm) ...[
            _Row(
              icon: Icons.person_outline,
              label: 'Client',
              value: _client?.displayName ?? 'None (whole firm)',
              muted: _client == null,
              onTap: _busy ? null : _pickClient,
              onClear: _client == null ? null : () => setState(() => _client = null),
            ),
            const SizedBox(height: 10),
          ],
          if (_isTemplate) ...[
            DropdownButtonFormField<ChecklistFrequency>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: [
                for (final f in ChecklistFrequency.values)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (f) => setState(() => _frequency = f ?? _frequency),
            ),
            const SizedBox(height: 10),
          ],
          _Row(
            icon: Icons.event_outlined,
            label: _isTemplate ? 'First run' : 'Date',
            value: _iso(_date),
            onTap: _busy ? null : () => _pickDate(end: false),
          ),
          if (_isTemplate) ...[
            const SizedBox(height: 10),
            _Row(
              icon: Icons.event_busy_outlined,
              label: 'Ends',
              value: _endDate == null ? 'Never' : _iso(_endDate!),
              muted: _endDate == null,
              onTap: _busy ? null : () => _pickDate(end: true),
              onClear: _endDate == null ? null : () => setState(() => _endDate = null),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _repeats,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stop after this many times (optional)',
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('STEPS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.inkSubtle)),
              ),
              if (!_isTemplate)
                TextButton.icon(
                  onPressed: _busy ? null : _useTemplate,
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('Copy from a template', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _steps,
            onChanged: (_) => setState(() {}),
            minLines: 6,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'One step per line\nReconcile bank accounts\nReview aging reports\nSend the monthly report',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            steps.isEmpty ? 'Nothing yet.' : '${steps.length} step${steps.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 12.5, color: AppColors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isTemplate ? 'Save template' : 'Create checklist',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            Icon(icon, size: 18, color: AppColors.inkMuted),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: muted ? AppColors.inkSubtle : AppColors.ink),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 16, color: AppColors.inkSubtle),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right, size: 16, color: AppColors.inkSubtle),
              ),
          ],
        ),
      ),
    );
  }
}
