// Budget provider — streams Rakhi's current-month budget doc from
// users/{userId}/finance/{yyyy-MM}. Auto-selects the current month at
// watch time; UI does not need to pass a key.
//
// When the doc doesn't exist yet (first-month user), emits
// `BudgetDoc.empty()` so the Finance screen can render defaults.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget_doc.dart';
import '../services/firestore_service.dart';

String _currentMonthKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

final budgetDocProvider =
    StreamProvider.family<BudgetDoc, String>((ref, userId) {
  final svc = FirestoreService();
  final key = _currentMonthKey();
  return svc.budgetStream(userId, key).map((raw) {
    if (raw == null) return BudgetDoc.empty();
    return BudgetDoc.fromMap(raw);
  });
});
