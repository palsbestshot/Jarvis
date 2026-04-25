// Time tracking + visit-log analytics section for the Board.
// Shows RAG pills (Revenue %, Admin %, Coverage %, Email min), a horizontal
// stacked bar breakdown by category, per-category bars, and the list of
// logs for the selected range (day/week/month).
//
// Reads time_logs via FirestoreService.streamTimeLogs...

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/time_categories.dart';
import '../../models/time_log.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import '../../widgets/log_time_sheet.dart';

enum TimeRange { day, week, month }

class TimeSection extends StatefulWidget {
  final UserProfile user;
  const TimeSection({super.key, required this.user});

  @override
  State<TimeSection> createState() => _TimeSectionState();
}

class _TimeSectionState extends State<TimeSection> {
  final _svc = FirestoreService();
  TimeRange _range = TimeRange.day;

  List<String> _rangeKeys() {
    final now = DateTime.now();
    final keys = <String>[];
    switch (_range) {
      case TimeRange.day:
        keys.add(FirestoreService.istDateKey(now));
        break;
      case TimeRange.week:
        for (int i = 6; i >= 0; i--) {
          keys.add(FirestoreService.istDateKey(
              now.subtract(Duration(days: i))));
        }
        break;
      case TimeRange.month:
        for (int i = 29; i >= 0; i--) {
          keys.add(FirestoreService.istDateKey(
              now.subtract(Duration(days: i))));
        }
        break;
    }
    return keys;
  }

  int _daysInRange() {
    switch (_range) {
      case TimeRange.day:
        return 1;
      case TimeRange.week:
        return 7;
      case TimeRange.month:
        return 30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _rangeKeys();
    final from = keys.first;
    final to = keys.last;
    return StreamBuilder<List<TimeLog>>(
      stream: _range == TimeRange.day
          ? _svc.streamTimeLogsForDate(widget.user.id, keys.first)
          : _svc.streamTimeLogsInRange(
              widget.user.id,
              fromDateKey: from,
              toDateKey: to,
            ),
      builder: (ctx, snap) {
        final logs = snap.data ?? const <TimeLog>[];
        final analytics =
            _svc.aggregateTimeLogs(logs, _daysInRange());
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _buildRangeToggle(),
            const SizedBox(height: 12),
            _buildHeadline(analytics),
            const SizedBox(height: 14),
            _buildRagPills(analytics),
            const SizedBox(height: 14),
            _buildStackedBar(analytics),
            const SizedBox(height: 14),
            _buildCategoryList(analytics),
            const SizedBox(height: 18),
            _buildQuickLogButtons(),
            const SizedBox(height: 18),
            _buildLogsListHeader(logs),
            for (final log in logs.take(_range == TimeRange.day ? 50 : 30))
              _buildLogTile(log),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 40, color: JarvisTheme.textMuted),
                      const SizedBox(height: 8),
                      Text(
                        'No logs for this range yet.\nTap "Log time" to start.',
                        style: JarvisTheme.bodySmall
                            .copyWith(color: JarvisTheme.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  // ──────────────────────── WIDGETS ────────────────────────────────────────
  Widget _buildRangeToggle() {
    final accent = widget.user.accentColor;
    Widget chip(TimeRange r, String label) {
      final active = _range == r;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _range = r),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? accent.withOpacity(0.2) : JarvisTheme.surface,
              borderRadius: BorderRadius.circular(8),
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
        ),
      );
    }

    return Row(
      children: [
        chip(TimeRange.day, 'Today'),
        const SizedBox(width: 6),
        chip(TimeRange.week, 'Last 7 days'),
        const SizedBox(width: 6),
        chip(TimeRange.month, 'Last 30 days'),
      ],
    );
  }

  Widget _buildHeadline(TimeAnalytics a) {
    final total = a.totalMin;
    final expected = _daysInRange() * 600; // 10h/day
    final logged = _fmtHM(total);
    final expectedStr = _fmtHM(expected);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer, color: widget.user.accentColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _rangeLabel(),
                  style: JarvisTheme.bodyLarge
                      .copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (a.logCount > 0)
                Flexible(
                  child: Text(
                    '${a.logCount} log${a.logCount == 1 ? '' : 's'}'
                    '${a.visitCount > 0 ? ' · ${a.visitCount} visit${a.visitCount == 1 ? '' : 's'}' : ''}',
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Logged $logged of $expectedStr',
            style: JarvisTheme.bodyMedium
                .copyWith(color: JarvisTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildRagPills(TimeAnalytics a) {
    final revenueBand = TimeRagThresholds.higherIsBetter(
      a.revenuePct,
      TimeRagThresholds.revenuePctGreen,
      TimeRagThresholds.revenuePctAmber,
    );
    final adminBand = TimeRagThresholds.lowerIsBetter(
      a.adminPct,
      TimeRagThresholds.adminPctGreen,
      TimeRagThresholds.adminPctAmber,
    );
    final coverageBand = TimeRagThresholds.higherIsBetter(
      a.coveragePct,
      TimeRagThresholds.coveragePctGreen,
      TimeRagThresholds.coveragePctAmber,
    );
    final emailBand = TimeRagThresholds.lowerIsBetter(
      a.emailMinPerDay,
      TimeRagThresholds.emailMinGreen,
      TimeRagThresholds.emailMinAmber,
    );
    return Column(
      children: [
        _buildPillRow(
          label: 'Revenue time',
          value: '${a.revenuePct.toStringAsFixed(0)}%',
          sub: _fmtHM(a.revenueMin),
          target: 'target 50%+',
          band: revenueBand,
        ),
        _buildPillRow(
          label: 'Admin / email / MIS',
          value: '${a.adminPct.toStringAsFixed(0)}%',
          sub: _fmtHM(a.adminPlusEmailMin),
          target: 'target <15%',
          band: adminBand,
        ),
        _buildPillRow(
          label: 'Day coverage',
          value: '${a.coveragePct.toStringAsFixed(0)}%',
          sub: _fmtHM(a.totalMin),
          target: 'target 85%+',
          band: coverageBand,
        ),
        _buildPillRow(
          label: 'Email time',
          value: '${a.emailMinPerDay.toStringAsFixed(0)} min/day',
          sub: _fmtHM(a.emailMin),
          target: 'target <20 min',
          band: emailBand,
        ),
      ],
    );
  }

  Widget _buildPillRow({
    required String label,
    required String value,
    required String sub,
    required String target,
    required RagBand band,
  }) {
    final color = TimeRagThresholds.colorFor(band);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: JarvisTheme.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$sub · $target',
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.6), width: 0.8),
            ),
            child: Text(
              value,
              style: JarvisTheme.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedBar(TimeAnalytics a) {
    if (a.totalMin == 0) return const SizedBox.shrink();
    final segments = <_BarSeg>[];
    for (final cat in TimeCategories.all) {
      final mins = a.byCategory[cat.id] ?? 0;
      if (mins <= 0) continue;
      segments.add(_BarSeg(cat: cat, mins: mins));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Breakdown',
          style: JarvisTheme.labelMedium
              .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: segments.map((s) {
              return Expanded(
                flex: s.mins,
                child: Tooltip(
                  message:
                      '${s.cat.label}: ${_fmtHM(s.mins)} (${(s.mins / a.totalMin * 100).toStringAsFixed(0)}%)',
                  child: Container(height: 14, color: s.cat.color),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryList(TimeAnalytics a) {
    if (a.totalMin == 0) return const SizedBox.shrink();
    final sorted = [...TimeCategories.all]..sort((x, y) =>
        (a.byCategory[y.id] ?? 0).compareTo(a.byCategory[x.id] ?? 0));
    return Column(
      children: sorted
          .where((c) => (a.byCategory[c.id] ?? 0) > 0)
          .map((c) {
        final mins = a.byCategory[c.id] ?? 0;
        final pct = (mins / a.totalMin * 100);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Icon(c.icon, size: 14, color: c.color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.label,
                            style: JarvisTheme.bodySmall,
                          ),
                        ),
                        Text(
                          '${_fmtHM(mins)} · ${pct.toStringAsFixed(0)}%',
                          style: JarvisTheme.bodySmall.copyWith(
                            color: JarvisTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Container(
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
                            color: c.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickLogButtons() {
    final accent = widget.user.accentColor;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => showLogTimeSheet(
              context: context,
              user: widget.user,
              initialMode: LogSheetMode.routine,
            ),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('Log time'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => showLogTimeSheet(
              context: context,
              user: widget.user,
              initialMode: LogSheetMode.visit,
            ),
            icon: Icon(Icons.place_outlined, size: 18, color: accent),
            label: Text('Log visit', style: TextStyle(color: accent)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: accent.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsListHeader(List<TimeLog> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            'Logs',
            style: JarvisTheme.labelMedium
                .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTile(TimeLog log) {
    final cat = TimeCategories.byId(log.categoryId) ?? TimeCategories.admin;
    final accent = widget.user.accentColor;
    return Dismissible(
      key: ValueKey(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.red.withOpacity(0.15),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                backgroundColor: JarvisTheme.surface,
                title:
                    Text('Delete log?', style: JarvisTheme.bodyLarge),
                content: Text(
                  'Remove "${log.activity}" from the timeline?',
                  style: JarvisTheme.bodyMedium,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        await _svc.deleteTimeLog(widget.user.id, log.id);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: JarvisTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: cat.color, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              log.isVisit ? Icons.place : cat.icon,
              size: 16,
              color: cat.color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          log.activity.isNotEmpty
                              ? log.activity
                              : cat.label,
                          style: JarvisTheme.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmtHM(log.durationMin),
                        style: JarvisTheme.bodySmall.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _logSubtitle(log, cat),
                    style: JarvisTheme.bodySmall.copyWith(
                      color: JarvisTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (log.isVisit &&
                      (log.visitDiscussion?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 3),
                    Text(
                      log.visitDiscussion!,
                      style: JarvisTheme.bodySmall.copyWith(
                        color: JarvisTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (log.isVisit &&
                      (log.visitNextSteps?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.arrow_right_alt,
                            size: 14, color: accent),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            log.visitNextSteps!,
                            style: JarvisTheme.bodySmall.copyWith(
                              color: JarvisTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (log.isRevenue)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'REV',
                    style: JarvisTheme.bodySmall.copyWith(
                      color: Colors.green.shade400,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────── UTILS ────────────────────────────────────────
  String _rangeLabel() {
    switch (_range) {
      case TimeRange.day:
        return 'Today';
      case TimeRange.week:
        return 'Last 7 days';
      case TimeRange.month:
        return 'Last 30 days';
    }
  }

  String _logSubtitle(TimeLog log, TimeCategory cat) {
    final parts = <String>[];
    if (log.isVisit) {
      final t = VisitContactTypes.byId(log.visitContactType)?.label ?? '';
      final who = log.visitPersonName ?? '';
      final co = log.visitCompany ?? '';
      if (t.isNotEmpty) parts.add(t);
      if (who.isNotEmpty) {
        parts.add(co.isNotEmpty ? '$who ($co)' : who);
      } else if (co.isNotEmpty) {
        parts.add(co);
      }
    } else {
      parts.add(cat.label);
      if (log.clientName != null && log.clientName!.isNotEmpty) {
        parts.add(log.clientName!);
      }
    }
    final at = log.startAt;
    if (at != null) {
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add('${two(at.hour)}:${two(at.minute)}');
    }
    return parts.join(' · ');
  }

  static String _fmtHM(int m) {
    if (m <= 0) return '0m';
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }
}

class _BarSeg {
  final TimeCategory cat;
  final int mins;
  _BarSeg({required this.cat, required this.mins});
}
