// "Log time" bottom sheet — two modes:
//   Routine: category + duration + revenue toggle + short activity note.
//   Visit:   routine fields + contact type + person/company + discussion +
//            next steps + optional follow-up date that creates a reminder.
//
// The docx's Phase 1B says the #1 failure mode is logging friction. So:
//   - Default the mode based on how the sheet was opened.
//   - Expose 1-tap duration presets (15m / 30m / 1h / 2h).
//   - Expose a "now - X min" shortcut so after-the-fact logging stays fast.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/time_categories.dart';
import '../models/time_log.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';

enum LogSheetMode { routine, visit }

Future<void> showLogTimeSheet({
  required BuildContext context,
  required UserProfile user,
  LogSheetMode initialMode = LogSheetMode.routine,
  TimeCategory? initialCategory,
  String? visitPersonName,
  String? visitCompany,
  String? visitContactType,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: JarvisTheme.surface2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _LogTimeSheet(
        user: user,
        initialMode: initialMode,
        initialCategory: initialCategory,
        visitPersonName: visitPersonName,
        visitCompany: visitCompany,
        visitContactType: visitContactType,
      );
    },
  );
}

class _LogTimeSheet extends StatefulWidget {
  final UserProfile user;
  final LogSheetMode initialMode;
  final TimeCategory? initialCategory;
  final String? visitPersonName;
  final String? visitCompany;
  final String? visitContactType;

  const _LogTimeSheet({
    required this.user,
    required this.initialMode,
    this.initialCategory,
    this.visitPersonName,
    this.visitCompany,
    this.visitContactType,
  });

  @override
  State<_LogTimeSheet> createState() => _LogTimeSheetState();
}

class _LogTimeSheetState extends State<_LogTimeSheet> {
  final _svc = FirestoreService();
  late LogSheetMode _mode;
  late TimeCategory _category;
  int _durationMin = 30;
  late bool _isRevenue;
  final _activityCtl = TextEditingController();
  final _clientCtl = TextEditingController();
  // Visit extras
  final _personCtl = TextEditingController();
  final _companyCtl = TextEditingController();
  final _locationCtl = TextEditingController();
  final _discussionCtl = TextEditingController();
  final _nextStepsCtl = TextEditingController();
  final _projectCtl = TextEditingController();
  String _contactType = VisitContactTypes.consultant.id;
  DateTime? _followupDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _category = widget.initialCategory ??
        (_mode == LogSheetMode.visit
            ? TimeCategories.client_meeting
            : TimeCategories.email);
    _isRevenue = _category.defaultRevenue;
    if (widget.visitPersonName != null) {
      _personCtl.text = widget.visitPersonName!;
    }
    if (widget.visitCompany != null) {
      _companyCtl.text = widget.visitCompany!;
    }
    if (widget.visitContactType != null) {
      _contactType = widget.visitContactType!;
    }
  }

  @override
  void dispose() {
    _activityCtl.dispose();
    _clientCtl.dispose();
    _personCtl.dispose();
    _companyCtl.dispose();
    _locationCtl.dispose();
    _discussionCtl.dispose();
    _nextStepsCtl.dispose();
    _projectCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    // Minimal validation
    if (_mode == LogSheetMode.visit && _personCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Who did you meet with?')),
      );
      return;
    }
    if (_durationMin <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a duration.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final startAt = now.subtract(Duration(minutes: _durationMin));
      final dateKey = FirestoreService.istDateKey(startAt);
      final log = TimeLog(
        id: '',
        kind: _mode == LogSheetMode.visit ? 'visit' : 'routine',
        date: DateTime(startAt.year, startAt.month, startAt.day),
        dateKey: dateKey,
        startAt: startAt,
        durationMin: _durationMin,
        categoryId: _category.id,
        isRevenue: _isRevenue,
        activity: _activityCtl.text.trim().isEmpty
            ? _category.label
            : _activityCtl.text.trim(),
        clientName: _clientCtl.text.trim().isEmpty
            ? null
            : _clientCtl.text.trim(),
        visitContactType:
            _mode == LogSheetMode.visit ? _contactType : null,
        visitPersonName: _mode == LogSheetMode.visit &&
                _personCtl.text.trim().isNotEmpty
            ? _personCtl.text.trim()
            : null,
        visitCompany: _mode == LogSheetMode.visit &&
                _companyCtl.text.trim().isNotEmpty
            ? _companyCtl.text.trim()
            : null,
        visitLocation: _mode == LogSheetMode.visit &&
                _locationCtl.text.trim().isNotEmpty
            ? _locationCtl.text.trim()
            : null,
        visitDiscussion: _mode == LogSheetMode.visit &&
                _discussionCtl.text.trim().isNotEmpty
            ? _discussionCtl.text.trim()
            : null,
        visitNextSteps: _mode == LogSheetMode.visit &&
                _nextStepsCtl.text.trim().isNotEmpty
            ? _nextStepsCtl.text.trim()
            : null,
        followupDate: _followupDate,
        projectName: _mode == LogSheetMode.visit &&
                _projectCtl.text.trim().isNotEmpty
            ? _projectCtl.text.trim()
            : null,
        source: 'manual',
      );

      final logId = await _svc.createTimeLog(userId: widget.user.id, log: log);

      // Visit follow-up → reminder so checkReminders fires at that time.
      if (_mode == LogSheetMode.visit && _followupDate != null) {
        final remindAt = _followupDate!;
        final reminderRef = FirebaseFirestore.instance
            .collection('users')
            .doc(widget.user.id)
            .collection('reminders')
            .doc();
        final subject = _companyCtl.text.trim().isNotEmpty
            ? '${_personCtl.text.trim()} (${_companyCtl.text.trim()})'
            : _personCtl.text.trim();
        await reminderRef.set({
          'message': 'Follow up on visit with $subject',
          'remind_at': Timestamp.fromDate(remindAt),
          'fired': false,
          'source': 'visit_followup',
          'time_log_id': logId,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          _mode == LogSheetMode.visit ? 'Visit logged.' : 'Logged $_durationMin min.',
        )),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.user.accentColor;
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: JarvisTheme.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Mode toggle
            Row(
              children: [
                _modeChip(LogSheetMode.routine, 'Routine', accent),
                const SizedBox(width: 8),
                _modeChip(LogSheetMode.visit, 'Visit', accent),
                const Spacer(),
                Text(
                  '${_durationMin} min',
                  style: JarvisTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Duration presets
            _fieldLabel('Duration'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [15, 30, 45, 60, 90, 120, 180]
                  .map((m) => _durationChip(m, accent))
                  .toList(),
            ),
            const SizedBox(height: 14),
            // Category picker
            _fieldLabel('Category'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: TimeCategories.all
                  .map((c) => _catChip(c, accent))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // Revenue toggle (default from category, user can flip)
            Row(
              children: [
                Switch(
                  value: _isRevenue,
                  onChanged: (v) => setState(() => _isRevenue = v),
                  activeColor: accent,
                ),
                const SizedBox(width: 8),
                Text(
                  _isRevenue
                      ? 'Counts as revenue-generating'
                      : 'Non-revenue / overhead',
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Short activity note (routine) / visit extras (visit)
            if (_mode == LogSheetMode.routine) ...[
              _fieldLabel('Activity (optional)'),
              const SizedBox(height: 6),
              _input(
                controller: _activityCtl,
                hint: 'e.g. Reviewed pipeline with Harshit',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _fieldLabel('Client / account (optional)'),
              const SizedBox(height: 6),
              _input(
                controller: _clientCtl,
                hint: 'e.g. TVS SCS Rohtak',
              ),
            ] else ...[
              _fieldLabel('Contact type'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: VisitContactTypes.all
                    .map((t) => _contactTypeChip(t, accent))
                    .toList(),
              ),
              const SizedBox(height: 10),
              _fieldLabel('Person *'),
              const SizedBox(height: 6),
              _input(controller: _personCtl, hint: 'Name'),
              const SizedBox(height: 10),
              _fieldLabel('Company / firm'),
              const SizedBox(height: 6),
              _input(controller: _companyCtl, hint: 'e.g. DLF, Synergy MEP'),
              const SizedBox(height: 10),
              _fieldLabel('Location'),
              const SizedBox(height: 6),
              _input(
                  controller: _locationCtl, hint: 'Site / city / their office'),
              const SizedBox(height: 10),
              _fieldLabel('Project (optional)'),
              const SizedBox(height: 6),
              _input(
                controller: _projectCtl,
                hint: 'e.g. Phoenix IT Park Chiller',
              ),
              const SizedBox(height: 10),
              _fieldLabel('Discussion'),
              const SizedBox(height: 6),
              _input(
                controller: _discussionCtl,
                hint:
                    'What was discussed — brief, scope, competitor, pain points…',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _fieldLabel('Next steps'),
              const SizedBox(height: 6),
              _input(
                controller: _nextStepsCtl,
                hint: 'e.g. Send revised quote by Thu, site visit next Mon',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.event,
                    size: 18,
                    color: JarvisTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _followupDate == null
                          ? 'No follow-up reminder set'
                          : 'Follow-up: ${_fmtDate(_followupDate!)}',
                      style: JarvisTheme.bodySmall.copyWith(
                        color: JarvisTheme.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickFollowup,
                    child: Text(
                      _followupDate == null ? 'Set' : 'Change',
                      style: TextStyle(color: accent),
                    ),
                  ),
                  if (_followupDate != null)
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: JarvisTheme.textMuted),
                      onPressed: () => setState(() => _followupDate = null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save log'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────── WIDGETS ────────────────────────────────────
  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: JarvisTheme.labelMedium
          .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: !_saving,
      style: JarvisTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
        filled: true,
        fillColor: JarvisTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _modeChip(LogSheetMode mode, String label, Color accent) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = mode;
          // Switching modes: retune default category.
          if (_mode == LogSheetMode.visit &&
              !_category.defaultRevenue) {
            _category = TimeCategories.client_meeting;
            _isRevenue = _category.defaultRevenue;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent.withOpacity(0.22) : JarvisTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? accent : JarvisTheme.surface2,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: JarvisTheme.bodySmall.copyWith(
            color: active ? accent : JarvisTheme.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _durationChip(int mins, Color accent) {
    final active = _durationMin == mins;
    return GestureDetector(
      onTap: () => setState(() => _durationMin = mins),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withOpacity(0.22) : JarvisTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? accent : JarvisTheme.surface2,
            width: 0.8,
          ),
        ),
        child: Text(
          _fmtMin(mins),
          style: JarvisTheme.bodySmall.copyWith(
            color: active ? accent : JarvisTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _catChip(TimeCategory c, Color accent) {
    final active = _category.id == c.id;
    return GestureDetector(
      onTap: () => setState(() {
        _category = c;
        _isRevenue = c.defaultRevenue; // auto-update — user can flip via switch
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.color.withOpacity(0.22) : JarvisTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? c.color : JarvisTheme.surface2,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.icon, size: 14, color: active ? c.color : JarvisTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              c.label,
              style: JarvisTheme.bodySmall.copyWith(
                color: active ? c.color : JarvisTheme.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTypeChip(VisitContactType t, Color accent) {
    final active = _contactType == t.id;
    return GestureDetector(
      onTap: () => setState(() => _contactType = t.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withOpacity(0.22) : JarvisTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? accent : JarvisTheme.surface2,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, size: 14, color: active ? accent : JarvisTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              t.label,
              style: JarvisTheme.bodySmall.copyWith(
                color: active ? accent : JarvisTheme.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFollowup() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followupDate ?? now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    final combined = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time?.hour ?? 10,
      time?.minute ?? 0,
    );
    if (mounted) setState(() => _followupDate = combined);
  }

  static String _fmtMin(int m) {
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  static String _fmtDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
