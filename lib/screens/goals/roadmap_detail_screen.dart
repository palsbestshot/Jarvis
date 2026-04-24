// Full-screen drilldown for roadmap-type goals.
// Renders phases → sections → checkpoints and wires up tick / notes / attach
// flows. Pushed from the Goals tab's hero card on board_screen.dart.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
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
        if (goal.phases.isNotEmpty) ...[
          _buildMilestoneTimeline(goal, accent),
          const SizedBox(height: JarvisTheme.md),
        ],
        _buildAttachmentCard(goal, accent),
        const SizedBox(height: JarvisTheme.md),
        ..._buildPhasePanels(goal, accent),
      ],
    );
  }

  // ─────────────────────────── HEADER ───────────────────────────────────────
  Widget _buildHeaderCard(Goal goal, Color accent) {
    final progress = goal.overallProgress;
    final target = goal.targetDate;
    final category = _deriveCategory(goal);
    final weeksLeft = target != null
        ? (target.difference(DateTime.now()).inDays / 7).ceil()
        : null;
    final onTrack = _onTrackLabel(goal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACTIVE · ${category.toUpperCase()}',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 11,
            color: accent,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: _splitTitleForEmphasis(goal.title, accent)),
          style: const TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 26,
            height: 1.2,
            color: JarvisTheme.textPrimary,
          ),
        ),
        if (goal.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            goal.description,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: JarvisTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JarvisTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JarvisTheme.surface2),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _headerStat(
                    label: 'OVERALL',
                    value: '${progress.toInt()}',
                    trailing: '%',
                  ),
                ),
                Container(width: 1, color: JarvisTheme.surface2),
                Expanded(
                  child: _headerStat(
                    label: 'ON TRACK',
                    value: onTrack,
                    valueColor: onTrack == 'Yes' ? accent : null,
                  ),
                ),
                Container(width: 1, color: JarvisTheme.surface2),
                Expanded(
                  child: _headerStat(
                    label: 'WEEKS LEFT',
                    value: weeksLeft == null
                        ? '—'
                        : (weeksLeft < 0 ? '0' : '$weeksLeft'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerStat({
    required String label,
    required String value,
    String? trailing,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 11,
              color: JarvisTheme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 22,
                color: valueColor ?? JarvisTheme.textPrimary,
              ),
              children: [
                if (trailing != null)
                  const TextSpan(
                    text: '%',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: JarvisTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _deriveCategory(Goal goal) {
    if (goal.phases.isNotEmpty) {
      final at = goal.phases.first.automationTarget.trim();
      if (at.isNotEmpty) return at;
    }
    final words = goal.title.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0]} ${words[1]}';
    if (words.isNotEmpty) return words.first;
    return 'ROADMAP';
  }

  String _onTrackLabel(Goal goal) {
    final start = goal.startDate;
    final target = goal.targetDate;
    if (start == null || target == null) return 'Yes';
    final now = DateTime.now();
    final total = target.difference(start).inMilliseconds;
    if (total <= 0) return goal.overallProgress >= 99 ? 'Yes' : 'Monitor';
    final elapsed = now.difference(start).inMilliseconds.clamp(0, total);
    final expected = (elapsed / total) * 100;
    return goal.overallProgress >= (expected - 10) ? 'Yes' : 'Monitor';
  }

  List<InlineSpan> _splitTitleForEmphasis(String title, Color accent) {
    final byRegex = RegExp(r'\s+by\s+', caseSensitive: false);
    final m = byRegex.firstMatch(title);
    if (m != null) {
      final head = title.substring(0, m.end);
      final tail = title.substring(m.end);
      if (tail.trim().isNotEmpty) {
        return [
          TextSpan(text: head),
          TextSpan(text: tail, style: TextStyle(color: accent)),
        ];
      }
    }
    final tokens = title.trim().split(RegExp(r'\s+'));
    if (tokens.length > 2) {
      final last = tokens.last;
      if (RegExp(r"^(Q[1-4].*|'?\d{2,4})$").hasMatch(last)) {
        final head = tokens.take(tokens.length - 1).join(' ');
        return [
          TextSpan(text: '$head '),
          TextSpan(text: last, style: TextStyle(color: accent)),
        ];
      }
    }
    return [TextSpan(text: title)];
  }

  // ─────────────────────────── MILESTONE TIMELINE ───────────────────────────
  Widget _buildMilestoneTimeline(Goal goal, Color accent) {
    final curIdx = goal.currentPhaseIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MILESTONES',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 11,
            color: JarvisTheme.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < goal.phases.length; i++)
          _buildMilestoneRow(
            phase: goal.phases[i],
            accent: accent,
            isLast: i == goal.phases.length - 1,
            state: goal.phases[i].isDone
                ? 'done'
                : (i == curIdx ? 'active' : 'pending'),
          ),
      ],
    );
  }

  Widget _buildMilestoneRow({
    required GoalPhase phase,
    required Color accent,
    required bool isLast,
    required String state,
  }) {
    final pct = phase.progress.toInt();
    final isDone = state == 'done';
    final isPending = state == 'pending';
    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 14,
              child: Column(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? accent : Colors.transparent,
                      border: Border.all(
                        color: isPending ? JarvisTheme.textMuted : accent,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isDone
                        ? const Text(
                            '✓',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: JarvisTheme.background,
                              height: 1,
                            ),
                          )
                        : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1,
                        color: JarvisTheme.surface2,
                        margin: const EdgeInsets.only(top: 4),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phase.title,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isPending
                            ? JarvisTheme.textSecondary
                            : JarvisTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: JarvisTheme.surface2,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (pct / 100).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '$pct%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 11,
                              color: JarvisTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

