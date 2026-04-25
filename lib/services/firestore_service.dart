import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../core/constants.dart';
import '../data/hvac_roadmap_seed.dart';
import '../models/time_log.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Helper method to get user document reference
  DocumentReference<Map<String, dynamic>> _userDoc(String userId) {
    return _firestore.collection(AppConstants.usersCollection).doc(userId);
  }

  // Helper method to get collection reference for a user
  CollectionReference<Map<String, dynamic>> _userCollection(
    String userId,
    String collection,
  ) {
    return _userDoc(userId).collection(collection);
  }

  // Tasks
  Future<List<Map<String, dynamic>>> getTasks(String userId) async {
    final snapshot = await _userCollection(userId, AppConstants.tasksCollection)
        .orderBy('created_at', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<String> createTask(String userId, Map<String, dynamic> data) async {
    final docRef = _userCollection(userId, AppConstants.tasksCollection).doc();
    final now = FieldValue.serverTimestamp();
    
    await docRef.set({
      ...data,
      'created_at': now,
      'updated_at': now,
    });
    
    return docRef.id;
  }

  Future<void> updateTask(
    String userId,
    String taskId,
    Map<String, dynamic> fields,
  ) async {
    await _userCollection(userId, AppConstants.tasksCollection)
        .doc(taskId)
        .update({
      ...fields,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteTask(String userId, String taskId) async {
    await _userCollection(userId, AppConstants.tasksCollection)
        .doc(taskId)
        .delete();
  }

  Future<void> markTaskDone(String userId, String taskId) async {
    await updateTask(userId, taskId, {
      'status': 'done',
      'completed_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> postponeTask(String userId, String taskId) async {
    // First get the current task data to read due_date and due_time
    final taskDoc = await _userCollection(userId, AppConstants.tasksCollection)
        .doc(taskId)
        .get();

    if (!taskDoc.exists) {
      throw Exception('Task not found');
    }

    final taskData = taskDoc.data() as Map<String, dynamic>;
    final currentDueDate = taskData['due_date']?.toString();

    // Postpone semantics: push the task forward by one day, but never
    // backwards. Overdue / no-date / today → tomorrow. Future date →
    // current+1. This way "postpone" always feels like deferral.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    DateTime newDate = tomorrow;
    if (currentDueDate != null && currentDueDate.isNotEmpty) {
      try {
        final parsed = DateTime.parse(currentDueDate);
        final advanced = DateTime(parsed.year, parsed.month, parsed.day)
            .add(const Duration(days: 1));
        if (advanced.isAfter(tomorrow)) newDate = advanced;
      } catch (_) {
        // Unparseable due_date → fall back to tomorrow.
      }
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final newDueDate = '${newDate.year}-${two(newDate.month)}-${two(newDate.day)}';

    // Preserve due_time only if it was set; never overwrite to null,
    // which would clear an existing value via Firestore update().
    final fields = <String, dynamic>{
      'due_date': newDueDate,
      'status': 'pending',
    };
    final dueTime = taskData['due_time']?.toString();
    if (dueTime != null && dueTime.isNotEmpty) {
      fields['due_time'] = dueTime;
    }
    await updateTask(userId, taskId, fields);
  }

  // Flip the draft_status flag on an email task to 'requested'. A
  // Power Automate flow polls for these and creates the actual Outlook
  // draft (reply or forward) using outlook_message_id / delegate_email on
  // the same task doc, then writes back 'ready' + draft_id + draft_weblink
  // (or 'error' + draft_error). Flutter streams the doc and flips the
  // button UI accordingly.
  Future<void> requestOutlookDraft(String userId, String taskId) async {
    await updateTask(userId, taskId, {
      'draft_status': 'requested',
      'draft_requested_at': FieldValue.serverTimestamp(),
      'draft_error': null,
    });
  }

  /// Clear all draft_* fields on a task — used by the "Cancel and reset"
  /// action when PA is stuck or the user changes their mind. Button flips
  /// back to "Create draft in Outlook" so a fresh tap re-requests.
  Future<void> resetOutlookDraft(String userId, String taskId) async {
    await _userCollection(userId, AppConstants.tasksCollection)
        .doc(taskId)
        .update({
      'draft_status': FieldValue.delete(),
      'draft_error': FieldValue.delete(),
      'draft_claimed_at': FieldValue.delete(),
      'draft_requested_at': FieldValue.delete(),
      'draft_id': FieldValue.delete(),
      'draft_weblink': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // ─── Time logs (activity + visit logging, analytics) ─────────────────────
  // Each log is a row in users/{uid}/time_logs/{id}. See models/time_log.dart
  // for the shape. Analytics aggregate by date_key range client-side — small
  // data per user (≤ 30 logs/day × 30 days = 900 docs/month), fine to fetch.

  CollectionReference<Map<String, dynamic>> _timeLogsRef(String userId) =>
      _userDoc(userId).collection('time_logs');

  /// Stream the time logs for a specific YYYY-MM-DD date key, newest first.
  Stream<List<TimeLog>> streamTimeLogsForDate(String userId, String dateKey) {
    return _timeLogsRef(userId)
        .where('date_key', isEqualTo: dateKey)
        .snapshots()
        .map((snap) {
      final logs = snap.docs.map(TimeLog.fromDoc).toList();
      logs.sort((a, b) {
        final sa = a.startAt ?? a.date;
        final sb = b.startAt ?? b.date;
        return sb.compareTo(sa);
      });
      return logs;
    });
  }

  /// Stream logs between two date keys (inclusive). Used for week/month views.
  Stream<List<TimeLog>> streamTimeLogsInRange(
    String userId, {
    required String fromDateKey,
    required String toDateKey,
  }) {
    return _timeLogsRef(userId)
        .where('date_key', isGreaterThanOrEqualTo: fromDateKey)
        .where('date_key', isLessThanOrEqualTo: toDateKey)
        .snapshots()
        .map((snap) {
      final logs = snap.docs.map(TimeLog.fromDoc).toList();
      logs.sort((a, b) {
        final sa = a.startAt ?? a.date;
        final sb = b.startAt ?? b.date;
        return sb.compareTo(sa);
      });
      return logs;
    });
  }

  /// Create a new time log entry. Returns the doc id.
  Future<String> createTimeLog({
    required String userId,
    required TimeLog log,
  }) async {
    final ref = _timeLogsRef(userId).doc();
    await ref.set({
      ...log.toMap(),
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> deleteTimeLog(String userId, String logId) async {
    await _timeLogsRef(userId).doc(logId).delete();
  }

  Future<void> updateTimeLog(
    String userId,
    String logId,
    Map<String, dynamic> fields,
  ) async {
    await _timeLogsRef(userId).doc(logId).update(fields);
  }

  /// Aggregate a list of logs into the analytics summary.
  /// Caller computes `daysInRange` (1 for today, 7 for week, etc.).
  TimeAnalytics aggregateTimeLogs(List<TimeLog> logs, int daysInRange) {
    if (logs.isEmpty) return TimeAnalytics.empty(daysInRange);
    int total = 0;
    int revenue = 0;
    int adminEmail = 0;
    int email = 0;
    int visits = 0;
    final byCat = <String, int>{};
    for (final log in logs) {
      total += log.durationMin;
      if (log.isRevenue) revenue += log.durationMin;
      final cat = log.categoryId;
      byCat[cat] = (byCat[cat] ?? 0) + log.durationMin;
      // "Admin/email time" per docx: email + admin + MIS reporting.
      if (cat == 'email' || cat == 'admin' || cat == 'mis') {
        adminEmail += log.durationMin;
      }
      if (cat == 'email') email += log.durationMin;
      if (log.isVisit) visits++;
    }
    return TimeAnalytics(
      totalMin: total,
      revenueMin: revenue,
      adminPlusEmailMin: adminEmail,
      emailMin: email,
      byCategory: byCat,
      logCount: logs.length,
      visitCount: visits,
      daysInRange: daysInRange,
    );
  }

  /// YYYY-MM-DD for the given local time (or now). For a multi-user
  /// IST-only app we just use local time since devices are in India.
  static String istDateKey([DateTime? dt]) {
    final ref = dt ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${ref.year}-${two(ref.month)}-${two(ref.day)}';
  }

  // ─── Contact map ──────────────────────────────────────────────────────────
  // Maps canonical person names (from PeopleDirectory) to phone numbers that
  // the user picked from their device address book. Used by the email task
  // sheet's one-tap call icon on delegate / from tiles.
  //
  // Stored at users/{userId}/contact_map/{personKey} with fields:
  //   { name, phone, updatedAt }.
  // personKey = PeopleDirectory.keyOf(name).

  Stream<QuerySnapshot<Map<String, dynamic>>> contactMapStream(String userId) {
    return _userDoc(userId).collection('contact_map').snapshots();
  }

  Future<Map<String, String>> getContactMap(String userId) async {
    final snap = await _userDoc(userId).collection('contact_map').get();
    return {
      for (final doc in snap.docs)
        doc.id: (doc.data()['phone'] ?? '').toString(),
    };
  }

  Future<void> setContactPhone({
    required String userId,
    required String personKey,
    required String name,
    required String phone,
  }) async {
    await _userDoc(userId).collection('contact_map').doc(personKey).set({
      'name': name,
      'phone': phone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeContactPhone({
    required String userId,
    required String personKey,
  }) async {
    await _userDoc(userId).collection('contact_map').doc(personKey).delete();
  }

  // ─── Call logs + follow-ups ───────────────────────────────────────────────
  // When the user taps the 📞 icon on a task or in Settings, they get a
  // followup sheet that captures call notes + picks a time to be reminded
  // (1h / 3h / 5h / tomorrow 10am / done). This method writes both:
  //   1. A log doc under users/{userId}/call_logs/ with the full record
  //      (notes, timestamp, linked task, resolution).
  //   2. If a followup time was chosen: a reminder doc under
  //      users/{userId}/reminders/ so checkReminders (1-min cron) fires
  //      an FCM at that time.
  //   3. If resolution == 'done' and linked to a task: marks the task done.
  //   4. If linked to a task: appends the call notes onto the task's
  //      existing `notes` field for context.
  Future<String> logCallAndFollowup({
    required String userId,
    required String personName,
    required String phone,
    String? taskId,
    required String notes,
    required String resolution, // 'done' | 'followup_1h' | 'followup_3h' | 'followup_5h' | 'followup_tomorrow_10' | 'skip'
    int callDurationMin = 0, // if > 0, also writes a time_log entry under "Calls" so analytics include it
  }) async {
    final now = DateTime.now();
    DateTime? followupAt;
    String followupLabel = '';
    switch (resolution) {
      case 'followup_1h':
        followupAt = now.add(const Duration(hours: 1));
        followupLabel = '1 hour later';
        break;
      case 'followup_3h':
        followupAt = now.add(const Duration(hours: 3));
        followupLabel = '3 hours later';
        break;
      case 'followup_5h':
        followupAt = now.add(const Duration(hours: 5));
        followupLabel = '5 hours later';
        break;
      case 'followup_tomorrow_10':
        // Tomorrow 10:00 IST = UTC+5:30. DateTime.now() already local;
        // assume device clock is on IST (Blue Star is in India).
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 10, 0);
        followupAt = tomorrow;
        followupLabel = 'tomorrow 10:00 AM';
        break;
    }

    // 1. Write the call log.
    final logRef = _userDoc(userId).collection('call_logs').doc();
    await logRef.set({
      'person_name': personName,
      'phone': phone,
      'task_id': taskId,
      'notes': notes,
      'resolution': resolution,
      'followup_at': followupAt != null ? Timestamp.fromDate(followupAt) : null,
      'followup_label': followupLabel,
      'called_at': FieldValue.serverTimestamp(),
      'duration_min': callDurationMin,
    });

    // 1b. Also create a time_log entry (category: calls) so the call
    //     shows up in the daily/weekly analytics — if duration > 0.
    if (callDurationMin > 0) {
      final startAt = now.subtract(Duration(minutes: callDurationMin));
      final tLog = TimeLog(
        id: '',
        kind: 'routine',
        date: DateTime(startAt.year, startAt.month, startAt.day),
        dateKey: istDateKey(startAt),
        startAt: startAt,
        durationMin: callDurationMin,
        categoryId: 'calls',
        isRevenue: true, // calls with team/clients/bosses → revenue bucket by default
        activity: 'Call with $personName'
            '${notes.trim().isEmpty ? '' : ' — ${notes.trim().substring(0, notes.trim().length.clamp(0, 80))}'}',
        clientName: personName,
        source: 'call',
      );
      await createTimeLog(userId: userId, log: tLog);
    }

    // 2. Schedule the follow-up reminder if needed.
    if (followupAt != null) {
      final reminderRef = _userDoc(userId).collection('reminders').doc();
      final preview = notes.trim().isNotEmpty
          ? ' — ${notes.trim().substring(0, notes.trim().length.clamp(0, 60))}'
          : '';
      await reminderRef.set({
        'message': 'Follow up with $personName$preview',
        'remind_at': Timestamp.fromDate(followupAt),
        'fired': false,
        'source': 'call_followup',
        'task_id': taskId,
        'call_log_id': logRef.id,
        'created_at': FieldValue.serverTimestamp(),
      });
    }

    // 3 + 4. Update the linked task if any.
    if (taskId != null && taskId.isNotEmpty) {
      final taskRef = _userCollection(userId, AppConstants.tasksCollection).doc(taskId);
      final updates = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };
      // Append call notes to the task's notes field (non-destructive).
      if (notes.trim().isNotEmpty) {
        final stamp = _fmtIstTimestamp(now);
        updates['notes'] = FieldValue.arrayUnion([
          '[$stamp] Call with $personName: ${notes.trim()}'
        ]);
      }
      if (resolution == 'done') {
        updates['status'] = 'done';
        updates['completed_at'] = FieldValue.serverTimestamp();
      }
      try {
        await taskRef.set(updates, SetOptions(merge: true));
      } catch (_) {
        // If notes field on the task is a plain string (not an array),
        // arrayUnion fails — fall back to a string append.
        final snap = await taskRef.get();
        final data = snap.data() ?? {};
        final existing = (data['notes'] ?? '').toString();
        final appended = notes.trim().isEmpty
            ? existing
            : '${existing.isEmpty ? '' : '$existing\n'}'
                '[${_fmtIstTimestamp(now)}] Call with $personName: ${notes.trim()}';
        final retry = <String, dynamic>{
          'notes': appended,
          'updated_at': FieldValue.serverTimestamp(),
        };
        if (resolution == 'done') {
          retry['status'] = 'done';
          retry['completed_at'] = FieldValue.serverTimestamp();
        }
        await taskRef.set(retry, SetOptions(merge: true));
      }
    }

    return logRef.id;
  }

  String _fmtIstTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // Recurring Tasks
  Future<String> createRecurringTask(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final docRef = _userCollection(userId, AppConstants.recurringTasksCollection).doc();
    
    await docRef.set({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });
    
    return docRef.id;
  }

  Future<void> deleteRecurringTask(String userId, String habitId) async {
    await _userCollection(userId, AppConstants.recurringTasksCollection)
        .doc(habitId)
        .delete();
  }

  Future<void> updateRecurringTask(
    String userId,
    String habitId,
    Map<String, dynamic> fields,
  ) async {
    await _userCollection(userId, AppConstants.recurringTasksCollection)
        .doc(habitId)
        .update({
      ...fields,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // Thoughts
  Future<List<Map<String, dynamic>>> getThoughts(String userId) async {
    final snapshot = await _userCollection(userId, AppConstants.thoughtsCollection)
        .orderBy('created_at', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<String> saveThought(String userId, Map<String, dynamic> data) async {
    final docRef = _userCollection(userId, AppConstants.thoughtsCollection).doc();

    await docRef.set({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  Future<void> updateThought(String userId, String thoughtId, Map<String, dynamic> fields) async {
    await _userCollection(userId, AppConstants.thoughtsCollection).doc(thoughtId).update(fields);
  }

  Future<void> deleteThought(String userId, String thoughtId) async {
    await _userCollection(userId, AppConstants.thoughtsCollection).doc(thoughtId).delete();
  }

  // Bugs — app-level issue tracker. Pallav reports bugs via chat;
  // dev sessions (Claude Code) query status=='new' at start, fix, and
  // mark them 'fixed'. Schema is flat and flexible so Claude can add
  // severity/screen fields later without migrations.
  Future<String> saveBug(String userId, Map<String, dynamic> data) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bugs')
        .doc();
    await docRef.set({
      ...data,
      'status': 'new',
      'reported_at': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  // Goals
  Future<List<Map<String, dynamic>>> getGoals(String userId) async {
    final snapshot = await _userCollection(userId, AppConstants.goalsCollection).get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<String> saveGoal(String userId, Map<String, dynamic> data) async {
    final docRef = _userCollection(userId, AppConstants.goalsCollection).doc();
    
    await docRef.set({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });
    
    return docRef.id;
  }

  Future<void> updateGoal(
    String userId,
    String goalId,
    Map<String, dynamic> fields,
  ) async {
    await _userCollection(userId, AppConstants.goalsCollection).doc(goalId).update(fields);
  }

  Future<void> deleteGoal(String userId, String goalId) async {
    await _userCollection(userId, AppConstants.goalsCollection).doc(goalId).delete();
  }

  /// Stream a single goal doc for live checkpoint updates.
  Stream<DocumentSnapshot<Map<String, dynamic>>> goalStream(
    String userId,
    String goalId,
  ) {
    return _userCollection(userId, AppConstants.goalsCollection)
        .doc(goalId)
        .snapshots();
  }

  /// Stream all goals for a user (ordered by created_at desc).
  Stream<QuerySnapshot<Map<String, dynamic>>> goalsStream(String userId) {
    return _userCollection(userId, AppConstants.goalsCollection)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  /// Idempotent seeder for the HVAC roadmap. If a goal with
  /// type='roadmap' and the same title already exists, returns its id
  /// without creating a duplicate.
  Future<String> seedHvacRoadmap(String userId) async {
    final col = _userCollection(userId, AppConstants.goalsCollection);
    final existing = await col
        .where('type', isEqualTo: 'roadmap')
        .where('title', isEqualTo: kHvacRoadmapSeed['title'])
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }
    final now = DateTime.now();
    final targetDate = DateTime(now.year + 2, now.month, now.day);
    final docRef = col.doc();
    await docRef.set({
      ...kHvacRoadmapSeed,
      'startDate': Timestamp.fromDate(now),
      'targetDate': Timestamp.fromDate(targetDate),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Toggle a single checkpoint's done state. Reads the whole goal doc,
  /// mutates one checkpoint in the nested phases/sections, writes back in
  /// a transaction to avoid clobbering concurrent edits.
  Future<void> toggleCheckpoint({
    required String userId,
    required String goalId,
    required String phaseId,
    required String sectionId,
    required String checkpointId,
    required bool done,
  }) async {
    final ref =
        _userCollection(userId, AppConstants.goalsCollection).doc(goalId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final phases = _mutateCheckpoint(
        List<dynamic>.from(data['phases'] ?? const []),
        phaseId: phaseId,
        sectionId: sectionId,
        checkpointId: checkpointId,
        mutate: (cp) {
          cp['status'] = done ? 'done' : 'pending';
          if (done) {
            cp['completedAt'] = Timestamp.now();
          } else {
            cp.remove('completedAt');
          }
        },
      );
      tx.update(ref, {
        'phases': phases,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Update the notes field on a specific checkpoint.
  Future<void> updateCheckpointNotes({
    required String userId,
    required String goalId,
    required String phaseId,
    required String sectionId,
    required String checkpointId,
    required String notes,
  }) async {
    final ref =
        _userCollection(userId, AppConstants.goalsCollection).doc(goalId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final phases = _mutateCheckpoint(
        List<dynamic>.from(data['phases'] ?? const []),
        phaseId: phaseId,
        sectionId: sectionId,
        checkpointId: checkpointId,
        mutate: (cp) {
          if (notes.trim().isEmpty) {
            cp.remove('notes');
          } else {
            cp['notes'] = notes;
          }
        },
      );
      tx.update(ref, {
        'phases': phases,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Upload a file (typically the roadmap .docx) to Firebase Storage under
  /// users/{userId}/goals/{goalId}/{fileName}. Stores the download URL and
  /// metadata on the goal doc. Returns the download URL.
  Future<String> uploadGoalAttachment({
    required String userId,
    required String goalId,
    required File file,
    required String fileName,
  }) async {
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('users')
        .child(userId)
        .child('goals')
        .child(goalId)
        .child(fileName);
    final uploadTask = await storageRef.putFile(file);
    final url = await uploadTask.ref.getDownloadURL();
    final size = await file.length();
    await _userCollection(userId, AppConstants.goalsCollection)
        .doc(goalId)
        .update({
      'attachmentUrl': url,
      'attachmentName': fileName,
      'attachmentSize': size,
      'uploadedAt': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return url;
  }

  /// Remove an attached file from Storage and clear attachment fields on the
  /// goal doc.
  Future<void> removeGoalAttachment({
    required String userId,
    required String goalId,
    required String fileName,
  }) async {
    try {
      await FirebaseStorage.instance
          .ref()
          .child('users')
          .child(userId)
          .child('goals')
          .child(goalId)
          .child(fileName)
          .delete();
    } catch (_) {
      // File may already be gone — proceed to clear metadata regardless.
    }
    await _userCollection(userId, AppConstants.goalsCollection)
        .doc(goalId)
        .update({
      'attachmentUrl': FieldValue.delete(),
      'attachmentName': FieldValue.delete(),
      'attachmentSize': FieldValue.delete(),
      'uploadedAt': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Walk phases → sections → checkpoints, apply `mutate` to the matching
  /// checkpoint, and return the new phases list ready to write back.
  List<dynamic> _mutateCheckpoint(
    List<dynamic> phases, {
    required String phaseId,
    required String sectionId,
    required String checkpointId,
    required void Function(Map<String, dynamic> cp) mutate,
  }) {
    for (final phase in phases) {
      if (phase is! Map) continue;
      if (phase['id']?.toString() != phaseId) continue;
      final sections = phase['sections'];
      if (sections is! List) continue;
      for (final section in sections) {
        if (section is! Map) continue;
        if (section['id']?.toString() != sectionId) continue;
        final cps = section['checkpoints'];
        if (cps is! List) continue;
        for (int i = 0; i < cps.length; i++) {
          final cp = cps[i];
          if (cp is! Map) continue;
          if (cp['id']?.toString() != checkpointId) continue;
          final mutable = Map<String, dynamic>.from(cp);
          mutate(mutable);
          cps[i] = mutable;
          break;
        }
        break;
      }
      break;
    }
    return phases;
  }

  // Finance (Pallav only)
  Future<List<Map<String, dynamic>>> getFinance(String userId) async {
    final snapshot = await _userCollection(userId, AppConstants.financeCollection).get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<String> saveFinance(String userId, Map<String, dynamic> data) async {
    final docRef = _userCollection(userId, AppConstants.financeCollection).doc();
    
    await docRef.set({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
    
    return docRef.id;
  }

  // Meals (Rakhi only)
  Future<List<Map<String, dynamic>>> getMeals(String userId) async {
    final snapshot = await _userCollection(userId, AppConstants.mealsCollection).get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<String> saveMeal(String userId, Map<String, dynamic> data) async {
    final docRef = _userCollection(userId, AppConstants.mealsCollection).doc();

    await docRef.set({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  // ── Dish catalog + meal plan (Rakhi's meal planner) ────────────────
  //
  // Two collections under users/{uid}/:
  //   - dish_catalog: one doc per dish (seed + custom)
  //   - meal_plans:   one doc per calendar day, doc id = date_key
  //
  // Writes are scoped per-userId so Pallav's and Rakhi's data are fully
  // separate (Rakhi is the only user that opens this feature today, but
  // the API stays user-agnostic for future-proofing).

  CollectionReference<Map<String, dynamic>> _dishCatalogRef(String userId) =>
      _userDoc(userId).collection('dish_catalog');

  CollectionReference<Map<String, dynamic>> _mealPlansRef(String userId) =>
      _userDoc(userId).collection('meal_plans');

  /// Seed the dish catalog from `IndianDishSeed` if the collection is
  /// currently empty. Idempotent — safe to call on every app open.
  Future<int> seedDishCatalog(
    String userId, {
    required List<Map<String, dynamic>> seedDishes,
  }) async {
    // Cheap existence check: fetch just one doc. If any exists, bail
    // out so we don't duplicate the seed every time Rakhi opens Meals.
    final probe = await _dishCatalogRef(userId).limit(1).get();
    if (probe.docs.isNotEmpty) return 0;
    // Use batch writes for atomicity + speed (Firestore caps at 500).
    final batch = _firestore.batch();
    int written = 0;
    for (final dish in seedDishes) {
      final dishId = (dish['id'] ?? '').toString();
      // Prefer the seed-provided id so we can reference it from tests
      // and migrations; if missing, Firestore generates one.
      final ref = dishId.isNotEmpty
          ? _dishCatalogRef(userId).doc(dishId)
          : _dishCatalogRef(userId).doc();
      // Strip the in-memory id from the doc body — the doc id IS the id.
      final body = Map<String, dynamic>.from(dish)..remove('id');
      batch.set(ref, {
        ...body,
        'created_at': FieldValue.serverTimestamp(),
      });
      written++;
      if (written >= 450) break; // stay under the 500 op cap with headroom
    }
    await batch.commit();
    return written;
  }

  /// Stream the dish catalog, most-used first. Search/filter happens
  /// client-side (the catalog is small — 80-200 dishes tops).
  Stream<List<Map<String, dynamic>>> dishCatalogStream(String userId) {
    return _dishCatalogRef(userId)
        .orderBy('times_used', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              m['id'] = d.id;
              return m;
            }).toList());
  }

  /// One-shot catalog fetch — used by `query_dishes` tool handler.
  Future<List<Map<String, dynamic>>> getDishCatalog(String userId) async {
    final snap = await _dishCatalogRef(userId)
        .orderBy('times_used', descending: true)
        .get();
    return snap.docs.map((d) {
      final m = d.data();
      m['id'] = d.id;
      return m;
    }).toList();
  }

  /// Create a Rakhi-added dish. Returns the new doc id.
  Future<String> createDish(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final ref = _dishCatalogRef(userId).doc();
    await ref.set({
      ...data,
      'is_custom': true,
      'times_used': 0,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Increment `times_used` — call after successfully setting a meal
  /// slot so the picker surfaces frequently-used dishes first.
  Future<void> incrementDishTimesUsed(String userId, String dishId) async {
    await _dishCatalogRef(userId).doc(dishId).set({
      'times_used': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  /// Stream one day's meal plan. `dateKey` is YYYY-MM-DD. The doc may
  /// not exist — UI shows an empty skeleton in that case.
  Stream<DocumentSnapshot<Map<String, dynamic>>> mealPlanDayStream(
    String userId,
    String dateKey,
  ) {
    return _mealPlansRef(userId).doc(dateKey).snapshots();
  }

  /// Stream all meal plans within a date range — used by the monthly
  /// calendar view. Inclusive on both ends. dateKeys are string-sortable
  /// because they're zero-padded YYYY-MM-DD.
  Stream<List<Map<String, dynamic>>> mealPlanRangeStream(
    String userId,
    String fromDateKey,
    String toDateKey,
  ) {
    return _mealPlansRef(userId)
        .where('date_key', isGreaterThanOrEqualTo: fromDateKey)
        .where('date_key', isLessThanOrEqualTo: toDateKey)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              m['id'] = d.id;
              return m;
            }).toList());
  }

  /// Set or clear a single meal slot. Pass null to clear. Uses merge
  /// writes so other slots in the same day doc are untouched.
  ///
  /// slot is the MealSlotId.value string: 'breakfast'|'brunch'|'lunch'|
  /// 'eve_snacks'|'dinner'.
  Future<void> setMealSlot(
    String userId,
    String dateKey,
    String slot,
    Map<String, dynamic>? slotValue,
  ) async {
    final ref = _mealPlansRef(userId).doc(dateKey);
    // Firestore merge semantics: explicit null clears a field; a map
    // overwrites it. We always write `date_key` + `updated_at` to be
    // safe on first write.
    await ref.set({
      'date_key': dateKey,
      slot: slotValue, // null → cleared
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Chat History
  Future<void> saveChatMessage(String userId, Map<String, dynamic> data) async {
    await _userCollection(userId, AppConstants.chatHistoryCollection).add({
      ...data,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> chatStream(String userId) {
    return _userCollection(userId, AppConstants.chatHistoryCollection)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Fetch the most recent N chat turns, oldest-first, for Claude context.
  Future<List<Map<String, dynamic>>> getRecentChats(String userId, {int limit = 10}) async {
    final snapshot = await _userCollection(userId, AppConstants.chatHistoryCollection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    final messages = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();

    // Return oldest-first so the API sees the natural conversation order.
    return messages.reversed.toList();
  }

  // Reminders
  Future<String> setReminder(String userId, Map<String, dynamic> data) async {
    final docRef = _userCollection(userId, AppConstants.remindersCollection).doc();
    
    // Ensure remind_at is stored as ISO string
    final Map<String, dynamic> reminderData = {
      ...data,
      'fired': false,
      'created_at': FieldValue.serverTimestamp(),
    };
    
    // Convert remind_at to ISO string if it's a DateTime
    if (data['remind_at'] is DateTime) {
      reminderData['remind_at'] = (data['remind_at'] as DateTime).toIso8601String();
    } else if (data['remind_at'] != null && data['remind_at'] is! String) {
      // Try to parse as DateTime and convert to ISO string
      try {
        final dateTime = DateTime.parse(data['remind_at'].toString());
        reminderData['remind_at'] = dateTime.toIso8601String();
      } catch (e) {
        // If parsing fails, keep as is
        reminderData['remind_at'] = data['remind_at'].toString();
      }
    }
    
    // Ensure task_id is never null (empty string instead)
    if (reminderData['task_id'] == null) {
      reminderData['task_id'] = '';
    }
    
    await docRef.set(reminderData);
    
    return docRef.id;
  }

  // Inbox Emails (Pallav only)
  // Fetches by receivedAt ordering only and filters client-side.
  // This avoids needing a composite index on (status, receivedAt).
  Future<List<Map<String, dynamic>>> getRecentEmails(
    String userId, {
    int daysBack = 1,
    String filter = 'all',
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    final cutoffStr = cutoff.toIso8601String();

    final snapshot = await _userCollection(userId, 'inbox_emails')
        .orderBy('receivedAt', descending: true)
        .limit(50)
        .get();

    final emails = snapshot.docs.map<Map<String, dynamic>>((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();

    // Date cutoff
    var filtered = emails.where((e) {
      final receivedAt = e['receivedAt']?.toString() ?? '';
      if (receivedAt.isEmpty) return true;
      return receivedAt.compareTo(cutoffStr) >= 0;
    }).toList();

    // Status filter
    if (filter == 'pending_triage') {
      filtered = filtered.where((e) => e['status'] == 'pending').toList();
    } else {
      filtered = filtered.where((e) => e['status'] == 'processed').toList();
    }

    // Importance filter
    if (filter == 'critical') {
      return filtered.where((e) => e['importance'] == 'critical').toList();
    } else if (filter == 'actionable') {
      return filtered.where((e) => e['importance'] == 'actionable').toList();
    }
    return filtered;
  }

  // Get recent data for AI context
  Future<Map<String, dynamic>> getRecentData(String userId) async {
    final tasks = await getTasks(userId);
    final thoughts = await getThoughts(userId);
    
    return {
      'tasks': tasks.take(5).toList(), // Last 5 tasks
      'thoughts': thoughts.take(5).toList(), // Last 5 thoughts
    };
  }
}