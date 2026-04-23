// TimeLog — one activity entry in users/{uid}/time_logs/{id}.
//
// Two kinds live in this collection:
//   kind='routine' — any logged activity (meeting, email burst, admin, etc.)
//   kind='visit'   — a specialised routine log with extra fields
//                    (person name/type, company, discussion, next steps).
//
// `is_revenue` is evaluated per-entry (defaults to the category's flag but
// the user can toggle at log time). Analytics roll up on category + this
// flag to produce the RAG pills.

import 'package:cloud_firestore/cloud_firestore.dart';

class TimeLog {
  final String id;
  final String kind; // 'routine' | 'visit'
  final DateTime date; // local calendar date of the activity (IST)
  final String dateKey; // YYYY-MM-DD — indexable
  final DateTime? startAt;
  final int durationMin; // always set — source of truth for analytics
  final String categoryId;
  final bool isRevenue;
  final String activity;
  final String? notes;
  final String? clientName;
  // Visit-only fields (null when kind='routine'):
  final String? visitContactType;
  final String? visitPersonName;
  final String? visitCompany;
  final String? visitLocation;
  final String? visitDiscussion;
  final String? visitNextSteps;
  final DateTime? followupDate;
  final String? projectName;
  final String source; // 'manual' | 'call' | 'voice' | 'task'
  final DateTime? createdAt;

  const TimeLog({
    required this.id,
    required this.kind,
    required this.date,
    required this.dateKey,
    required this.durationMin,
    required this.categoryId,
    required this.isRevenue,
    required this.activity,
    this.startAt,
    this.notes,
    this.clientName,
    this.visitContactType,
    this.visitPersonName,
    this.visitCompany,
    this.visitLocation,
    this.visitDiscussion,
    this.visitNextSteps,
    this.followupDate,
    this.projectName,
    this.source = 'manual',
    this.createdAt,
  });

  bool get isVisit => kind == 'visit';

  factory TimeLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? <String, dynamic>{};
    return TimeLog(
      id: doc.id,
      kind: (m['kind'] ?? 'routine').toString(),
      date: _ts(m['date']) ?? DateTime.now(),
      dateKey: (m['date_key'] ?? '').toString(),
      startAt: _ts(m['start_at']),
      durationMin: (m['duration_min'] is num)
          ? (m['duration_min'] as num).toInt()
          : 0,
      categoryId: (m['category_id'] ?? 'admin').toString(),
      isRevenue: m['is_revenue'] == true,
      activity: (m['activity'] ?? '').toString(),
      notes: m['notes']?.toString(),
      clientName: m['client_name']?.toString(),
      visitContactType: m['visit_contact_type']?.toString(),
      visitPersonName: m['visit_person_name']?.toString(),
      visitCompany: m['visit_company']?.toString(),
      visitLocation: m['visit_location']?.toString(),
      visitDiscussion: m['visit_discussion']?.toString(),
      visitNextSteps: m['visit_next_steps']?.toString(),
      followupDate: _ts(m['followup_date']),
      projectName: m['project_name']?.toString(),
      source: (m['source'] ?? 'manual').toString(),
      createdAt: _ts(m['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'kind': kind,
      'date': Timestamp.fromDate(date),
      'date_key': dateKey,
      if (startAt != null) 'start_at': Timestamp.fromDate(startAt!),
      'duration_min': durationMin,
      'category_id': categoryId,
      'is_revenue': isRevenue,
      'activity': activity,
      if (notes != null) 'notes': notes,
      if (clientName != null) 'client_name': clientName,
      if (visitContactType != null) 'visit_contact_type': visitContactType,
      if (visitPersonName != null) 'visit_person_name': visitPersonName,
      if (visitCompany != null) 'visit_company': visitCompany,
      if (visitLocation != null) 'visit_location': visitLocation,
      if (visitDiscussion != null) 'visit_discussion': visitDiscussion,
      if (visitNextSteps != null) 'visit_next_steps': visitNextSteps,
      if (followupDate != null) 'followup_date': Timestamp.fromDate(followupDate!),
      if (projectName != null) 'project_name': projectName,
      'source': source,
    };
  }

  static DateTime? _ts(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

// Aggregation result for a date range (day/week/month).
class TimeAnalytics {
  final int totalMin;          // sum across all logs in range
  final int revenueMin;        // sum where is_revenue == true
  final int adminPlusEmailMin; // sum of email + admin + mis category ids
  final int emailMin;          // just category 'email'
  final Map<String, int> byCategory; // categoryId → minutes
  final int logCount;
  final int visitCount;
  final int daysInRange; // number of calendar days this range covers

  const TimeAnalytics({
    required this.totalMin,
    required this.revenueMin,
    required this.adminPlusEmailMin,
    required this.emailMin,
    required this.byCategory,
    required this.logCount,
    required this.visitCount,
    required this.daysInRange,
  });

  double get revenuePct => totalMin == 0 ? 0 : (revenueMin / totalMin) * 100;
  double get adminPct =>
      totalMin == 0 ? 0 : (adminPlusEmailMin / totalMin) * 100;
  // Coverage: how much of the assumed 10h workday (×days) we logged.
  double get coveragePct {
    if (daysInRange == 0) return 0;
    final expected = daysInRange * 600; // 10h * 60 = 600 min
    if (expected == 0) return 0;
    return (totalMin / expected) * 100;
  }

  double get emailMinPerDay =>
      daysInRange == 0 ? 0 : emailMin / daysInRange;

  static TimeAnalytics empty(int daysInRange) => TimeAnalytics(
        totalMin: 0,
        revenueMin: 0,
        adminPlusEmailMin: 0,
        emailMin: 0,
        byCategory: const {},
        logCount: 0,
        visitCount: 0,
        daysInRange: daysInRange,
      );
}
