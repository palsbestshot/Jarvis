// Call + Follow-up bottom sheet.
//
// Opens when the user taps the 📞 icon on an email task's delegate/from row
// or on a person tile in Settings. Flow:
//   1. Sheet opens with the person's name + phone.
//   2. "Call now" launches tel: — dialler takes over, sheet stays behind.
//   3. When the user comes back to Jarvis the sheet is still there.
//   4. They type what was discussed and pick one of:
//        [+1h] [+3h] [+5h] [Tomorrow 10am] [Mark task done] [Cancel]
//   5. FirestoreService.logCallAndFollowup writes the call_log doc,
//      a reminder doc (if followup time chosen), and appends the notes
//      to the linked task.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';

enum CallResolution {
  done,
  followup1h,
  followup3h,
  followup5h,
  followupTomorrow10,
  skip,
}

extension _ResolutionCode on CallResolution {
  String get code {
    switch (this) {
      case CallResolution.done:
        return 'done';
      case CallResolution.followup1h:
        return 'followup_1h';
      case CallResolution.followup3h:
        return 'followup_3h';
      case CallResolution.followup5h:
        return 'followup_5h';
      case CallResolution.followupTomorrow10:
        return 'followup_tomorrow_10';
      case CallResolution.skip:
        return 'skip';
    }
  }

  String get label {
    switch (this) {
      case CallResolution.done:
        return 'Mark task done';
      case CallResolution.followup1h:
        return 'Remind in 1h';
      case CallResolution.followup3h:
        return 'Remind in 3h';
      case CallResolution.followup5h:
        return 'Remind in 5h';
      case CallResolution.followupTomorrow10:
        return 'Tomorrow 10 AM';
      case CallResolution.skip:
        return 'No follow-up';
    }
  }

  IconData get icon {
    switch (this) {
      case CallResolution.done:
        return Icons.check_circle_outline;
      case CallResolution.followup1h:
      case CallResolution.followup3h:
      case CallResolution.followup5h:
        return Icons.schedule;
      case CallResolution.followupTomorrow10:
        return Icons.wb_sunny_outlined;
      case CallResolution.skip:
        return Icons.close;
    }
  }
}

Future<void> showCallFollowupSheet({
  required BuildContext context,
  required UserProfile user,
  required String personName,
  required String phone,
  String? taskId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: JarvisTheme.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _CallFollowupSheet(
        user: user,
        personName: personName,
        phone: phone,
        taskId: taskId,
      );
    },
  );
}

class _CallFollowupSheet extends StatefulWidget {
  final UserProfile user;
  final String personName;
  final String phone;
  final String? taskId;

  const _CallFollowupSheet({
    required this.user,
    required this.personName,
    required this.phone,
    this.taskId,
  });

  @override
  State<_CallFollowupSheet> createState() => _CallFollowupSheetState();
}

class _CallFollowupSheetState extends State<_CallFollowupSheet> {
  final TextEditingController _notesController = TextEditingController();
  final FirestoreService _svc = FirestoreService();
  bool _calledAtLeastOnce = false;
  bool _saving = false;
  DateTime? _calledAt;
  // Call duration — set when the user picks a duration chip. If 0, the
  // call doesn't write a time_log entry. Defaults to 0 (off) until the
  // user taps "Call now" — then auto-seeds to 5 min.
  int _durationMin = 0;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _dial() async {
    final uri = Uri.parse('tel:${widget.phone.replaceAll(' ', '')}');
    try {
      await launchUrl(uri);
      setState(() {
        _calledAtLeastOnce = true;
        _calledAt ??= DateTime.now();
        if (_durationMin == 0) _durationMin = 5; // seed with 5 min
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialler: $e')),
      );
    }
  }

  Future<void> _submit(CallResolution resolution) async {
    if (resolution == CallResolution.done && widget.taskId == null) {
      // "Mark task done" is only meaningful when invoked from a task.
      // Fallback: treat it as skip.
      resolution = CallResolution.skip;
    }
    setState(() => _saving = true);
    try {
      await _svc.logCallAndFollowup(
        userId: widget.user.id,
        personName: widget.personName,
        phone: widget.phone,
        taskId: widget.taskId,
        notes: _notesController.text.trim(),
        resolution: resolution.code,
        callDurationMin: _durationMin,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final msg = () {
        switch (resolution) {
          case CallResolution.done:
            return 'Marked done. Call notes saved.';
          case CallResolution.followup1h:
            return "Got it. I'll nudge you in 1 hour.";
          case CallResolution.followup3h:
            return "Got it. I'll nudge you in 3 hours.";
          case CallResolution.followup5h:
            return "Got it. I'll nudge you in 5 hours.";
          case CallResolution.followupTomorrow10:
            return "Got it. I'll nudge you tomorrow at 10 AM.";
          case CallResolution.skip:
            return 'Call notes saved. No follow-up scheduled.';
        }
      }();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
            // drag handle
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
            // Header — who + phone
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accent.withOpacity(0.22),
                  child: Text(
                    widget.personName.isNotEmpty
                        ? widget.personName[0]
                        : '?',
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.personName,
                        style: JarvisTheme.bodyLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.phone,
                        style: JarvisTheme.bodySmall
                            .copyWith(color: JarvisTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _dial,
                  icon: Icon(
                    _calledAtLeastOnce ? Icons.call_made : Icons.call,
                    size: 18,
                  ),
                  label: Text(_calledAtLeastOnce ? 'Call again' : 'Call now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Call duration — optional, feeds time analytics under "Calls"
            Text(
              'Call length (logs to your time analytics)',
              style: JarvisTheme.labelMedium
                  .copyWith(color: JarvisTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [0, 5, 10, 15, 20, 30, 45, 60].map((m) {
                final active = _durationMin == m;
                return GestureDetector(
                  onTap: () => setState(() => _durationMin = m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? accent.withOpacity(0.22)
                          : JarvisTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active ? accent : JarvisTheme.surface2,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      m == 0 ? "don't log" : '${m}m',
                      style: JarvisTheme.bodySmall.copyWith(
                        color: active ? accent : JarvisTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Notes capture
            Text(
              'What was discussed?',
              style: JarvisTheme.labelMedium
                  .copyWith(color: JarvisTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 4,
              style: JarvisTheme.bodyMedium,
              enabled: !_saving,
              decoration: InputDecoration(
                hintText:
                    'Quick summary — decisions, next steps, commitments…',
                hintStyle: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textMuted),
                filled: true,
                fillColor: JarvisTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Follow-up',
              style: JarvisTheme.labelMedium
                  .copyWith(color: JarvisTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            // Time-based follow-up buttons — wrap for narrow screens.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _followupChip(CallResolution.followup1h, accent),
                _followupChip(CallResolution.followup3h, accent),
                _followupChip(CallResolution.followup5h, accent),
                _followupChip(CallResolution.followupTomorrow10, accent),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.taskId != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _saving ? null : () => _submit(CallResolution.done),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark task done'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade400,
                    side: BorderSide(color: Colors.green.shade700),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed:
                    _saving ? null : () => _submit(CallResolution.skip),
                child: Text(
                  'Save notes only — no follow-up',
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _followupChip(CallResolution res, Color accent) {
    return ElevatedButton.icon(
      onPressed: _saving ? null : () => _submit(res),
      icon: Icon(res.icon, size: 16),
      label: Text(res.label),
      style: ElevatedButton.styleFrom(
        backgroundColor: accent.withOpacity(0.22),
        foregroundColor: accent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: accent.withOpacity(0.5), width: 0.8),
        ),
      ),
    );
  }
}
