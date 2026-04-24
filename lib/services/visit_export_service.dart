// Visit CSV export service.
//
// Queries users/{uid}/time_logs where kind='visit' in a date range, builds
// an RFC-4180 CSV with UTF-8 BOM (so Excel renders Hindi correctly), writes
// to the temp dir, and fires the platform share sheet so Pallav can email
// it to himself or push it into any CRM's bulk-import UI.
//
// Invoked from two places: the export bottom sheet in the Board > Time
// section, and the `export_visits` Claude chat tool.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/time_log.dart';
import '../services/firestore_service.dart';

class VisitExportResult {
  final int count;
  final String fromKey;
  final String toKey;
  const VisitExportResult({
    required this.count,
    required this.fromKey,
    required this.toKey,
  });
}

class VisitExportService {
  /// Build the CSV for visits in [from]..[to] (inclusive, IST calendar
  /// dates) and open the platform share sheet. Returns a result with the
  /// row count so callers can show a confirmation message.
  ///
  /// If no visits match, skips the share sheet and returns count=0 so the
  /// caller can surface a "nothing to share" hint.
  Future<VisitExportResult> exportAndShare({
    required String userId,
    required DateTime from,
    required DateTime to,
    String? contactType,
  }) async {
    final fromKey = FirestoreService.istDateKey(from);
    final toKey = FirestoreService.istDateKey(to);

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('time_logs')
        .where('kind', isEqualTo: 'visit')
        .where('date_key', isGreaterThanOrEqualTo: fromKey)
        .where('date_key', isLessThanOrEqualTo: toKey);
    if (contactType != null && contactType.isNotEmpty) {
      q = q.where('visit_contact_type', isEqualTo: contactType);
    }

    final snap = await q.get();
    final logs = snap.docs.map(TimeLog.fromDoc).toList();
    // Oldest first in the CSV so Excel's natural row order matches the
    // visit timeline.
    logs.sort((a, b) {
      final sa = a.startAt ?? a.date;
      final sb = b.startAt ?? b.date;
      return sa.compareTo(sb);
    });

    if (logs.isEmpty) {
      return VisitExportResult(count: 0, fromKey: fromKey, toKey: toKey);
    }

    final csv = _buildCsv(logs);
    final dir = await getTemporaryDirectory();
    final filename = 'jarvis_visits_${fromKey}_to_$toKey.csv';
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsString(csv, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: filename)],
      subject: 'Jarvis visits $fromKey to $toKey',
    );

    return VisitExportResult(
      count: logs.length,
      fromKey: fromKey,
      toKey: toKey,
    );
  }

  String _buildCsv(List<TimeLog> logs) {
    const header = [
      'date',
      'contact_type',
      'person_name',
      'company',
      'location',
      'project_name',
      'client_name',
      'duration_min',
      'discussion',
      'next_steps',
      'followup_date',
      'notes',
      'source',
      'created_at',
    ];
    final buf = StringBuffer();
    buf.write('\uFEFF'); // UTF-8 BOM - Excel reads Hindi/Unicode correctly.
    buf.writeln(header.map(_csv).join(','));
    for (final l in logs) {
      final row = <String>[
        l.dateKey.isNotEmpty
            ? l.dateKey
            : FirestoreService.istDateKey(l.date),
        l.visitContactType ?? '',
        l.visitPersonName ?? '',
        l.visitCompany ?? '',
        l.visitLocation ?? '',
        l.projectName ?? '',
        l.clientName ?? '',
        l.durationMin.toString(),
        l.visitDiscussion ?? '',
        l.visitNextSteps ?? '',
        l.followupDate != null
            ? FirestoreService.istDateKey(l.followupDate!)
            : '',
        l.notes ?? '',
        l.source,
        l.createdAt?.toIso8601String() ?? '',
      ];
      buf.writeln(row.map(_csv).join(','));
    }
    return buf.toString();
  }

  /// RFC-4180 cell quoting: wrap in double quotes, double-up any internal
  /// double quotes, preserve newlines inside cells (Excel handles them
  /// inside quoted fields).
  static String _csv(String raw) {
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
  }
}
