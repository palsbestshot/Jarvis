// Full-screen drilldown for roadmap-type goals.
// Renders phases → sections → checkpoints and wires up tick / notes / attach
// flows. Pushed from the Goals tab's hero card on board_screen.dart.

import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/goal.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';

class RoadmapDetailScreen extends StatefulWidget {
  final UserProfile user;
  final String goalId;

  const RoadmapDetailScreen({
    super.key,
    required this.user,
    required this.goalId,
  });

  @override
  State<RoadmapDetailScreen> createState() => _RoadmapDetailScreenState();
}

class _RoadmapDetailScreenState extends State<RoadmapDetailScreen> {
  final FirestoreService _svc = FirestoreService();
  final Set<String> _manuallyExpanded = {}; // phaseId overrides
  final Set<String> _manuallyCollapsed = {};

  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      appBar: AppBar(
        backgroundColor: JarvisTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: JarvisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Roadmap',
          style: JarvisTheme.headingMedium,
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _svc.goalStream(widget.user.id, widget.goalId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return Center(
              child: Text(
                'This goal was deleted.',
                style: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textSecondary),
              ),
            );
          }
          final goal =
              Goal.fromDoc(snap.data!, widget.user.id);
          return _buildBody(goal);
        },
      ),
    );
  }

  // ───────────────────────────── BODY ───────────────────────────────────────
  Widget _buildBody(Goal goal) {
    final accent = widget.user.accentColor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        JarvisTheme.md,
        JarvisTheme.sm,
        JarvisTheme.md,
        JarvisTheme.xxl,
      ),
      children: [
        _buildHeaderCard(goal, accent),
        const SizedBox(height: JarvisTheme.md),
        _buildAttachmentCard(goal, accent),
        const SizedBox(height: JarvisTheme.md),
        ..._buildPhasePanels(goal, accent),
      ],
    );
  }

  // ─────────────────────────── HEADER ───────────────────────────────────────
  Widget _buildHeaderCard(Goal goal, Color accent) {
    final progress = goal.overallProgress;
    final start = goal.startDate;
    final target = goal.targetDate;
    return Container(
      padding: const EdgeInsets.all(JarvisTheme.md),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(JarvisTheme.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            goal.title,
            style: JarvisTheme.headingLarge,
          ),
          const SizedBox(height: JarvisTheme.xs),
          Text(
            [
              if (start != null) 'Started ${AppUtils.formatDate(start.toIso8601String())}',
              if (target != null) 'Target ${AppUtils.formatDate(target.toIso8601String())}',
              '${goal.doneCheckpoints} of ${goal.totalCheckpoints} done',
            ].join(' · '),
            style: JarvisTheme.bodySmall
                .copyWith(color: JarvisTheme.textSecondary),
          ),
          const SizedBox(height: JarvisTheme.md),
          Row(
            children: [
              _ProgressRing(
                progress: progress,
                color: accent,
                size: 64,
                strokeWidth: 7,
              ),
              const SizedBox(width: JarvisTheme.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${progress.toInt()}% complete',
                      style: JarvisTheme.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    _ProgressBar(progress: progress, color: accent),
                    const SizedBox(height: 6),
                    if (goal.currentPhase != null)
                      Text(
                        'On Phase ${goal.currentPhaseIndex + 1} · ${goal.currentPhase!.title}',
                        style: JarvisTheme.bodySmall
                            .copyWith(color: JarvisTheme.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── ATTACHMENT ───────────────────────────────────
  Widget _buildAttachmentCard(Goal goal, Color accent) {
    return Container(
      padding: const EdgeInsets.all(JarvisTheme.md),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(JarvisTheme.medium),
      ),
      child: goal.hasAttachment
          ? _attachmentPresent(goal, accent)
          : _attachmentEmpty(goal, accent),
    );
  }

  Widget _attachmentPresent(Goal goal, Color accent) {
    final size = goal.attachmentSize;
    final sizeLabel = size != null ? _fmtBytes(size) : '';
    return Row(
      children: [
        Icon(Icons.description, color: accent, size: 26),
        const SizedBox(width: JarvisTheme.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.attachmentName ?? 'Source document',
                style: JarvisTheme.bodyMedium
                    .copyWith(fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (sizeLabel.isNotEmpty)
                Text(
                  sizeLabel,
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textMuted),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _openAttachment(goal.attachmentUrl!),
          child: Text(
            'Open',
            style: TextStyle(color: accent, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: _isUploading ? null : () => _pickAndUploadAttachment(goal),
          child: Text(
            _isUploading ? '…' : 'Replace',
            style: TextStyle(color: JarvisTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _attachmentEmpty(Goal goal, Color accent) {
    return Row(
      children: [
        Icon(Icons.upload_file, color: accent, size: 26),
        const SizedBox(width: JarvisTheme.sm),
        Expanded(
          child: Text(
            'Attach the source document so you can reopen it anytime.',
            style: JarvisTheme.bodySmall
                .copyWith(color: JarvisTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : () => _pickAndUploadAttachment(goal),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JarvisTheme.small),
            ),
          ),
          child: Text(_isUploading ? 'Uploading…' : 'Upload'),
        ),
      ],
    );
  }

  // ─────────────────────────── PHASES ───────────────────────────────────────
  List<Widget> _buildPhasePanels(Goal goal, Color accent) {
    final List<Widget> out = [];
    for (int i = 0; i < goal.phases.length; i++) {
      final phase = goal.phases[i];
      final isCurrent = i == goal.currentPhaseIndex;
      // Default: only current phase expanded unless user toggled.
      final overrideOpen = _manuallyExpanded.contains(phase.id);
      final overrideClosed = _manuallyCollapsed.contains(phase.id);
      final expanded =
          overrideOpen || (isCurrent && !overrideClosed);
      out.add(_buildPhaseCard(goal, phase, i, expanded, isCurrent, accent));
      out.add(const SizedBox(height: JarvisTheme.sm));
    }
    return out;
  }

  Widget _buildPhaseCard(
    Goal goal,
    GoalPhase phase,
    int index,
    bool expanded,
    bool isCurrent,
    Color accent,
  ) {
    final progress = phase.progress;
    return Container(
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(JarvisTheme.medium),
        border: Border.all(
          color: isCurrent
              ? accent.withOpacity(0.5)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (expanded) {
                  _manuallyExpanded.remove(phase.id);
                  _manuallyCollapsed.add(phase.id);
                } else {
                  _manuallyCollapsed.remove(phase.id);
                  _manuallyExpanded.add(phase.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(JarvisTheme.medium),
            child: Padding(
              padding: const EdgeInsets.all(JarvisTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: JarvisTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Phase ${index + 1} · ${phase.title}',
                          style: JarvisTheme.bodyLarge
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (!isCurrent && progress < 100)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: JarvisTheme.textMuted,
                          ),
                        ),
                      const SizedBox(width: JarvisTheme.sm),
                      Text(
                        '${progress.toInt()}%',
                        style: JarvisTheme.bodySmall.copyWith(
                          color: isCurrent
                              ? accent
                              : JarvisTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${phase.monthsLabel} · ${phase.automationTarget}',
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  _ProgressBar(progress: progress, color: accent),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Container(
              height: 1,
              color: JarvisTheme.surface2,
              margin: const EdgeInsets.symmetric(horizontal: JarvisTheme.md),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                JarvisTheme.md,
                JarvisTheme.sm,
                JarvisTheme.md,
                JarvisTheme.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Focus: ${phase.focus}',
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textSecondary),
                  ),
                  const SizedBox(height: JarvisTheme.sm),
                  for (final section in phase.sections)
                    _buildSection(goal, phase, section, accent),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    Goal goal,
    GoalPhase phase,
    GoalSection section,
    Color accent,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: JarvisTheme.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: JarvisTheme.sm,
        vertical: JarvisTheme.sm,
      ),
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: BorderRadius.circular(JarvisTheme.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${section.id.toUpperCase()} · ${section.title}',
                  style: JarvisTheme.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${section.doneCount}/${section.checkpoints.length}',
                style: JarvisTheme.bodySmall.copyWith(
                  color: JarvisTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (section.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              section.summary,
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textMuted),
            ),
          ],
          const SizedBox(height: 6),
          for (final cp in section.checkpoints)
            _buildCheckpointRow(goal, phase, section, cp, accent),
        ],
      ),
    );
  }

  Widget _buildCheckpointRow(
    Goal goal,
    GoalPhase phase,
    GoalSection section,
    Checkpoint cp,
    Color accent,
  ) {
    final done = cp.isDone;
    final hasNotes = (cp.notes != null && cp.notes!.trim().isNotEmpty);
    return InkWell(
      onTap: () => _openNotesSheet(goal, phase, section, cp),
      borderRadius: BorderRadius.circular(JarvisTheme.small),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _toggleCheckpoint(goal, phase, section, cp, !done),
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: done ? accent : Colors.transparent,
                  border: Border.all(
                    color: done ? accent : JarvisTheme.textMuted,
                    width: 1.4,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: done
                    ? const Icon(Icons.check,
                        size: 16, color: Colors.black)
                    : null,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cp.title,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: done
                          ? JarvisTheme.textMuted
                          : JarvisTheme.textPrimary,
                      decoration:
                          done ? TextDecoration.lineThrough : TextDecoration.none,
                      decorationColor: JarvisTheme.textMuted,
                    ),
                  ),
                  if (hasNotes) ...[
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined,
                            size: 12, color: JarvisTheme.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            cp.notes!,
                            style: JarvisTheme.bodySmall.copyWith(
                              color: JarvisTheme.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────── ACTIONS ─────────────────────────────────────
  Future<void> _toggleCheckpoint(
    Goal goal,
    GoalPhase phase,
    GoalSection section,
    Checkpoint cp,
    bool done,
  ) async {
    try {
      await _svc.toggleCheckpoint(
        userId: widget.user.id,
        goalId: goal.id,
        phaseId: phase.id,
        sectionId: section.id,
        checkpointId: cp.id,
        done: done,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    }
  }

  Future<void> _openNotesSheet(
    Goal goal,
    GoalPhase phase,
    GoalSection section,
    Checkpoint cp,
  ) async {
    final controller = TextEditingController(text: cp.notes ?? '');
    final accent = widget.user.accentColor;
    await showModalBottomSheet(
      context: context,
      backgroundColor: JarvisTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: JarvisTheme.md,
          right: JarvisTheme.md,
          top: JarvisTheme.md,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + JarvisTheme.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cp.title,
              style: JarvisTheme.bodyLarge
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: JarvisTheme.xs),
            Text(
              '${section.id.toUpperCase()} · ${section.title}',
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textMuted),
            ),
            const SizedBox(height: JarvisTheme.md),
            TextField(
              controller: controller,
              maxLines: 5,
              style: JarvisTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Notes, links, context…',
                hintStyle: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textMuted),
                filled: true,
                fillColor: JarvisTheme.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(JarvisTheme.small),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: JarvisTheme.md),
            Row(
              children: [
                TextButton(
                  onPressed: () => _toggleAndClose(goal, phase, section, cp),
                  child: Text(
                    cp.isDone ? 'Mark pending' : 'Mark done',
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: JarvisTheme.sm),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await _svc.updateCheckpointNotes(
                      userId: widget.user.id,
                      goalId: goal.id,
                      phaseId: phase.id,
                      sectionId: section.id,
                      checkpointId: cp.id,
                      notes: controller.text.trim(),
                    );
                    if (mounted && Navigator.canPop(ctx)) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAndClose(
    Goal goal,
    GoalPhase phase,
    GoalSection section,
    Checkpoint cp,
  ) async {
    await _toggleCheckpoint(goal, phase, section, cp, !cp.isDone);
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _openAttachment(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the document.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Open failed: $e')));
      }
    }
  }

  Future<void> _pickAndUploadAttachment(Goal goal) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['docx', 'doc', 'pdf'],
      );
      if (result == null || result.files.isEmpty) return;
      final pf = result.files.first;
      final path = pf.path;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'This platform returned no file path — try another picker.')));
        }
        return;
      }
      setState(() => _isUploading = true);
      await _svc.uploadGoalAttachment(
        userId: widget.user.id,
        goalId: goal.id,
        file: File(path),
        fileName: pf.name,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document attached.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ────────────────────────────── UTILS ─────────────────────────────────────
  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─────────────────────────── REUSABLE WIDGETS ───────────────────────────────
class _ProgressRing extends StatelessWidget {
  final double progress; // 0..100
  final Color color;
  final double size;
  final double strokeWidth;

  const _ProgressRing({
    required this.progress,
    required this.color,
    required this.size,
    this.strokeWidth = 6,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: 1,
              color: JarvisTheme.surface2,
              strokeWidth: strokeWidth,
            ),
          ),
          if (progress > 0)
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                progress: (progress / 100).clamp(0, 1),
                color: color,
                strokeWidth: strokeWidth,
              ),
            ),
          Text(
            '${progress.toInt()}%',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: size * 0.28,
              fontWeight: FontWeight.w600,
              color: JarvisTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _ProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (progress / 100).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
