// Time tracking section for the Board — visual refresh per JARVIS DESIGN
// handoff (pallav-screens.jsx · PallavTime). Layout:
//   • range toggle (Today / 7d / 30d) + export icon
//   • 7-day Mon→Sun vertical bar chart (current week, independent of range)
//   • summary card: day/range label + Serif 30pt total + stacked cat bar + legend
//   • RECENT ENTRIES list with 95pt time col + description + accent category
//
// Preserves: range-scoped aggregation via FirestoreService.aggregateTimeLogs,
// swipe-to-delete on each row, Log time / Log visit quick buttons at bottom.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/time_categories.dart';
import '../../models/time_log.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import '../../widgets/export_visits_sheet.dart';
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

  static const _weekdayShort = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayFull = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  DateTime _weekStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime _weekEnd() => _weekStart().add(const Duration(days: 6));

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
    final weekStartKey = FirestoreService.istDateKey(_weekStart());
    final weekEndKey = FirestoreService.istDateKey(_weekEnd());
    return StreamBuilder<List<TimeLog>>(
      stream: _svc.streamTimeLogsInRange(
        widget.user.id,
        fromDateKey: weekStartKey,
        toDateKey: weekEndKey,
      ),
      builder: (ctx, weekSnap) {
        final weekLogs = weekSnap.data ?? const <TimeLog>[];
        final keys = _rangeKeys();
        return StreamBuilder<List<TimeLog>>(
          stream: _range == TimeRange.day
              ? _svc.streamTimeLogsForDate(widget.user.id, keys.first)
              : _svc.streamTimeLogsInRange(
                  widget.user.id,
                  fromDateKey: keys.first,
                  toDateKey: keys.last,
                ),
          builder: (ctx2, rangeSnap) {
            final logs = rangeSnap.data ?? const <TimeLog>[];
            final analytics =
                _svc.aggregateTimeLogs(logs, _daysInRange());
            return ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _buildRangeToggle(),
                const SizedBox(height: 16),
                _buildWeekBars(weekLogs),
                const SizedBox(height: 14),
                _buildSummaryCard(analytics, weekLogs),
                const SizedBox(height: 4),
                _buildRecentHeader(),
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
                const SizedBox(height: 18),
                _buildQuickLogButtons(),
                const SizedBox(height: 40),
              ],
            );
          },
        );
      },
    );
  }

  // ──────────────────────── RANGE TOGGLE ───────────────────────────────────
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
              color: active ? accent.withOpacity(0.14) : JarvisTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? accent.withOpacity(0.4)
                    : JarvisTheme.surface2,
                width: 0.8,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
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
        const SizedBox(width: 6),
        InkWell(
          onTap: () => showExportVisitsSheet(
            context: context,
            user: widget.user,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: JarvisTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: JarvisTheme.surface2,
                width: 0.8,
              ),
            ),
            child: Icon(
              Icons.ios_share,
              size: 16,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────── 7-DAY BARS ─────────────────────────────────────
  Widget _buildWeekBars(List<TimeLog> weekLogs) {
    final accent = widget.user.accentColor;
    final weekStart = _weekStart();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final perDay = List<int>.filled(7, 0);
    for (final log in weekLogs) {
      final at = log.startAt;
      if (at == null) continue;
      final d = DateTime(at.year, at.month, at.day);
      final idx = d.difference(weekStart).inDays;
      if (idx >= 0 && idx < 7) perDay[idx] += log.durationMin;
    }
    final maxMin = perDay.fold<int>(0, math.max);

    return Row(
      children: List.generate(7, (i) {
        final dayDate = weekStart.add(Duration(days: i));
        final isToday = dayDate.difference(today).inDays == 0;
        final mins = perDay[i];
        final pct = maxMin == 0 ? 0.0 : mins / maxMin;
        final hours = mins / 60.0;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
            child: Column(
              children: [
                Text(
                  _weekdayShort[i],
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 10,
                    color: JarvisTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: JarvisTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isToday ? accent : JarvisTheme.surface2,
                      width: 1,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: pct.clamp(0.0, 1.0),
                      widthFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isToday ? accent : JarvisTheme.surface3,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_fmtDec(hours)}h',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 10,
                    color: isToday ? accent : JarvisTheme.textSecondary,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ──────────────────────── SUMMARY CARD ───────────────────────────────────
  Widget _buildSummaryCard(TimeAnalytics a, List<TimeLog> weekLogs) {
    final accent = widget.user.accentColor;
    final totalHours = a.totalMin / 60.0;

    // "Xm vs avg" — only shown in day range, compared to 7-day avg/day.
    String? trend;
    if (_range == TimeRange.day && weekLogs.isNotEmpty) {
      final weekTotal = weekLogs.fold<int>(0, (s, l) => s + l.durationMin);
      final avgPerDay = weekTotal / 7;
      final diff = a.totalMin - avgPerDay;
      if (diff.abs() >= 5) {
        final mins = diff.abs().round();
        final h = mins ~/ 60;
        final m = mins % 60;
        final str = h > 0
            ? (m == 0 ? '${h}h' : '${h}h ${m}m')
            : '${m}m';
        trend = '${diff >= 0 ? '▲' : '▼'} $str vs avg';
      }
    }

    // Stacked segments sorted by magnitude.
    final segs = <MapEntry<TimeCategory, int>>[];
    for (final cat in TimeCategories.all) {
      final m = a.byCategory[cat.id] ?? 0;
      if (m > 0) segs.add(MapEntry(cat, m));
    }
    segs.sort((x, y) => y.value.compareTo(x.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JarvisTheme.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _summaryLabel(),
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 11,
                        color: JarvisTheme.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: _fmtDec(totalHours),
                            style: const TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 30,
                              color: JarvisTheme.textPrimary,
                            ),
                          ),
                          const TextSpan(
                            text: ' h logged',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 14,
                              color: JarvisTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (trend != null)
                Text(
                  trend,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (segs.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: segs
                      .map((e) => Expanded(
                            flex: e.value,
                            child: Container(color: e.key.color),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Column(
              children: segs.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: e.key.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.key.label,
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            color: JarvisTheme.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        _fmtHM(e.value),
                        style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: JarvisTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────── RECENT ENTRIES ─────────────────────────────────
  Widget _buildRecentHeader() {
    return const Padding(
      padding: EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        'RECENT ENTRIES',
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          color: JarvisTheme.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildLogTile(TimeLog log) {
    final cat = TimeCategories.byId(log.categoryId) ?? TimeCategories.admin;
    final accent = widget.user.accentColor;
    final desc = log.activity.isNotEmpty ? log.activity : cat.label;
    final timeStr = _timeRangeText(log);

    // Visit subtitle (e.g. "@ Ravi (Godrej)")
    String? visitDetail;
    if (log.isVisit) {
      final who = log.visitPersonName ?? '';
      final co = log.visitCompany ?? '';
      if (who.isNotEmpty || co.isNotEmpty) {
        visitDetail = who.isNotEmpty
            ? (co.isNotEmpty ? '@ $who ($co)' : '@ $who')
            : '@ $co';
      }
    }

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
                title: Text('Delete log?', style: JarvisTheme.bodyLarge),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: JarvisTheme.surface2, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 95,
              child: Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 12,
                  color: JarvisTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desc,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: JarvisTheme.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cat.label,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: accent,
                    ),
                  ),
                  if (visitDetail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      visitDetail,
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 11,
                        color: JarvisTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (log.isVisit &&
                      (log.visitNextSteps?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.arrow_right_alt, size: 14, color: accent),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            log.visitNextSteps!,
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 11,
                              color: JarvisTheme.textPrimary,
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
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 9,
                      color: Colors.green.shade400,
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

  // ──────────────────────── QUICK LOG BUTTONS ──────────────────────────────
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

  // ──────────────────────── UTILS ──────────────────────────────────────────
  String _summaryLabel() {
    switch (_range) {
      case TimeRange.day:
        final now = DateTime.now();
        return '${_weekdayFull[now.weekday - 1]} · TODAY';
      case TimeRange.week:
        return 'LAST 7 DAYS';
      case TimeRange.month:
        return 'LAST 30 DAYS';
    }
  }

  String _timeRangeText(TimeLog log) {
    final at = log.startAt;
    if (at != null) {
      final end = at.add(Duration(minutes: log.durationMin));
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(at.hour)}:${two(at.minute)} – ${two(end.hour)}:${two(end.minute)}';
    }
    return _fmtHM(log.durationMin);
  }

  // "5.5" → "5.5", "8.0" → "8", "0.25" → "0.3" (1dp). Matches JSX toFixed(1)
  // with trailing .0 stripped for cleaner reads at small sizes.
  static String _fmtDec(double h) {
    final s = h.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String _fmtHM(int m) {
    if (m <= 0) return '0m';
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }
}
