// Goal model — supports both simple flat goals and structured "roadmap" goals
// with phases → sections → checkpoints.
//
// A simple goal (the original shape) has type='simple', empty phases, and
// its progress field is a percentage the user edits directly.
//
// A roadmap goal has type='roadmap' and a non-empty phases[] array. Its
// overallProgress is computed from the checkpoints (ignored as a stored
// field and derived on read). Roadmap goals can optionally have an attached
// source document (Firebase Storage URL) the user can reopen anytime.

import 'package:cloud_firestore/cloud_firestore.dart';

// ──────────────────────────── CHECKPOINT ────────────────────────────────────
class Checkpoint {
  final String id;
  final String title;
  final String status; // 'pending' | 'in_progress' | 'done'
  final DateTime? completedAt;
  final String? notes;

  const Checkpoint({
    required this.id,
    required this.title,
    this.status = 'pending',
    this.completedAt,
    this.notes,
  });

  bool get isDone => status == 'done';

  factory Checkpoint.fromMap(Map<String, dynamic> map) {
    return Checkpoint(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      completedAt: _parseTimestamp(map['completedAt']),
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'status': status,
        if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
        if (notes != null) 'notes': notes,
      };

  Checkpoint copyWith({
    String? status,
    DateTime? completedAt,
    String? notes,
    bool clearCompletedAt = false,
  }) {
    return Checkpoint(
      id: id,
      title: title,
      status: status ?? this.status,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      notes: notes ?? this.notes,
    );
  }
}

// ────────────────────────────── SECTION ─────────────────────────────────────
class GoalSection {
  final String id;
  final String title;
  final String summary;
  final List<Checkpoint> checkpoints;

  const GoalSection({
    required this.id,
    required this.title,
    required this.summary,
    required this.checkpoints,
  });

  double get progress {
    if (checkpoints.isEmpty) return 0;
    final done = checkpoints.where((c) => c.isDone).length;
    return (done / checkpoints.length) * 100;
  }

  int get doneCount => checkpoints.where((c) => c.isDone).length;

  factory GoalSection.fromMap(Map<String, dynamic> map) {
    final rawCps = map['checkpoints'];
    final cps = <Checkpoint>[];
    if (rawCps is List) {
      for (final c in rawCps) {
        if (c is Map) {
          cps.add(Checkpoint.fromMap(Map<String, dynamic>.from(c)));
        }
      }
    }
    return GoalSection(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      summary: (map['summary'] ?? '').toString(),
      checkpoints: cps,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'summary': summary,
        'checkpoints': checkpoints.map((c) => c.toMap()).toList(),
      };
}

// ────────────────────────────── PHASE ───────────────────────────────────────
class GoalPhase {
  final String id;
  final String title;
  final String monthsLabel;
  final int monthStart;
  final int monthEnd;
  final String focus;
  final String automationTarget;
  final List<GoalSection> sections;

  const GoalPhase({
    required this.id,
    required this.title,
    required this.monthsLabel,
    required this.monthStart,
    required this.monthEnd,
    required this.focus,
    required this.automationTarget,
    required this.sections,
  });

  int get totalCheckpoints =>
      sections.fold(0, (acc, s) => acc + s.checkpoints.length);

  int get doneCheckpoints => sections.fold(0, (acc, s) => acc + s.doneCount);

  double get progress {
    if (totalCheckpoints == 0) return 0;
    return (doneCheckpoints / totalCheckpoints) * 100;
  }

  bool get isDone => totalCheckpoints > 0 && doneCheckpoints == totalCheckpoints;

  factory GoalPhase.fromMap(Map<String, dynamic> map) {
    final rawSections = map['sections'];
    final sections = <GoalSection>[];
    if (rawSections is List) {
      for (final s in rawSections) {
        if (s is Map) {
          sections.add(GoalSection.fromMap(Map<String, dynamic>.from(s)));
        }
      }
    }
    return GoalPhase(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      monthsLabel: (map['monthsLabel'] ?? '').toString(),
      monthStart: _toInt(map['monthStart']),
      monthEnd: _toInt(map['monthEnd']),
      focus: (map['focus'] ?? '').toString(),
      automationTarget: (map['automationTarget'] ?? '').toString(),
      sections: sections,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'monthsLabel': monthsLabel,
        'monthStart': monthStart,
        'monthEnd': monthEnd,
        'focus': focus,
        'automationTarget': automationTarget,
        'sections': sections.map((s) => s.toMap()).toList(),
      };
}

// ─────────────────────────────── GOAL ───────────────────────────────────────
class Goal {
  final String id;
  final String title;
  final String description;
  final String type; // 'simple' | 'roadmap'
  final String status; // 'active' | 'paused' | 'done'
  final DateTime? startDate;
  final DateTime? targetDate;
  final double storedProgress; // used only for simple goals
  final List<GoalPhase> phases;
  final String? attachmentUrl;
  final String? attachmentName;
  final int? attachmentSize;
  final DateTime? uploadedAt;
  final String userId;

  const Goal({
    required this.id,
    required this.title,
    required this.description,
    this.type = 'simple',
    this.status = 'active',
    this.startDate,
    this.targetDate,
    this.storedProgress = 0,
    this.phases = const [],
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentSize,
    this.uploadedAt,
    required this.userId,
  });

  bool get isRoadmap => type == 'roadmap';

  bool get hasAttachment =>
      (attachmentUrl != null && attachmentUrl!.isNotEmpty);

  int get totalCheckpoints =>
      phases.fold(0, (acc, p) => acc + p.totalCheckpoints);

  int get doneCheckpoints =>
      phases.fold(0, (acc, p) => acc + p.doneCheckpoints);

  /// For roadmap goals, derived from checkpoints. For simple goals, the
  /// stored value set by the user.
  double get overallProgress {
    if (!isRoadmap) return storedProgress;
    if (totalCheckpoints == 0) return 0;
    return (doneCheckpoints / totalCheckpoints) * 100;
  }

  /// First phase where progress < 100. Falls through to the last phase index
  /// if every phase is complete.
  int get currentPhaseIndex {
    if (phases.isEmpty) return 0;
    for (int i = 0; i < phases.length; i++) {
      if (phases[i].progress < 100) return i;
    }
    return phases.length - 1;
  }

  GoalPhase? get currentPhase =>
      phases.isEmpty ? null : phases[currentPhaseIndex];

  /// Up-to-N unticked checkpoints from the current phase, for the hero card
  /// "next up" preview.
  List<Checkpoint> nextUp({int limit = 3}) {
    final result = <Checkpoint>[];
    if (phases.isEmpty) return result;
    // Start from current phase, spill to later phases only if current is done.
    for (int i = currentPhaseIndex; i < phases.length; i++) {
      for (final section in phases[i].sections) {
        for (final c in section.checkpoints) {
          if (!c.isDone) {
            result.add(c);
            if (result.length >= limit) return result;
          }
        }
      }
    }
    return result;
  }

  factory Goal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc, String userId) {
    final map = doc.data() ?? <String, dynamic>{};
    return Goal.fromMap(doc.id, map, userId);
  }

  factory Goal.fromMap(String id, Map<String, dynamic> map, String userId) {
    final rawPhases = map['phases'];
    final phases = <GoalPhase>[];
    if (rawPhases is List) {
      for (final p in rawPhases) {
        if (p is Map) {
          phases.add(GoalPhase.fromMap(Map<String, dynamic>.from(p)));
        }
      }
    }
    return Goal(
      id: id,
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      type: (map['type'] ?? 'simple').toString(),
      status: (map['status'] ?? 'active').toString(),
      startDate: _parseTimestamp(map['startDate']) ??
          _parseTimestamp(map['created_at']),
      targetDate:
          _parseTimestamp(map['targetDate']) ?? _parseTimestamp(map['target_date']),
      storedProgress: _toDouble(map['progress']),
      phases: phases,
      attachmentUrl: map['attachmentUrl']?.toString(),
      attachmentName: map['attachmentName']?.toString(),
      attachmentSize:
          map['attachmentSize'] is num ? (map['attachmentSize'] as num).toInt() : null,
      uploadedAt: _parseTimestamp(map['uploadedAt']),
      userId: userId,
    );
  }
}

// ─────────────────────────────── HELPERS ────────────────────────────────────
DateTime? _parseTimestamp(dynamic raw) {
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

int _toInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

double _toDouble(dynamic raw) {
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? 0;
  return 0;
}
