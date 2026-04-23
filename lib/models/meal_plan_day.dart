// MealPlanDay — one doc at users/{uid}/meal_plans/{yyyy-mm-dd}.
// Holds up to 5 meal slots for a single calendar day. The calendar view
// shows a month of these at a glance; tapping a day opens MealDayDetail.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'dish.dart';

class MealSlot {
  final String dishId;
  final String? notes;

  const MealSlot({required this.dishId, this.notes});

  factory MealSlot.fromMap(Map<String, dynamic>? m) {
    if (m == null) {
      throw ArgumentError('MealSlot.fromMap got null');
    }
    return MealSlot(
      dishId: (m['dish_id'] ?? '').toString(),
      notes: m['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dish_id': dishId,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }

  MealSlot copyWith({String? dishId, String? notes}) {
    return MealSlot(
      dishId: dishId ?? this.dishId,
      notes: notes ?? this.notes,
    );
  }
}

class MealPlanDay {
  /// YYYY-MM-DD — matches the Firestore doc id.
  final String dateKey;
  /// Keyed by slot; missing or null value means "not planned".
  final Map<MealSlotId, MealSlot?> slots;
  final DateTime? updatedAt;

  const MealPlanDay({
    required this.dateKey,
    required this.slots,
    this.updatedAt,
  });

  MealSlot? slot(MealSlotId id) => slots[id];

  /// True if the day has any slot planned — used by the calendar view to
  /// decide whether to draw the dots under the date number.
  bool get hasAnyPlanned =>
      slots.values.any((v) => v != null && v.dishId.isNotEmpty);

  /// How many of the 5 slots are planned. The calendar uses this for
  /// a subtle progress indicator on day cells.
  int get plannedCount =>
      slots.values.where((v) => v != null && v.dishId.isNotEmpty).length;

  factory MealPlanDay.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? <String, dynamic>{};
    final dateKey = (m['date_key'] ?? doc.id).toString();
    final slots = <MealSlotId, MealSlot?>{};
    for (final slotId in MealSlotId.values) {
      final raw = m[slotId.value];
      if (raw is Map<String, dynamic>) {
        try {
          slots[slotId] = MealSlot.fromMap(raw);
        } catch (_) {
          slots[slotId] = null;
        }
      } else {
        slots[slotId] = null;
      }
    }
    return MealPlanDay(
      dateKey: dateKey,
      slots: slots,
      updatedAt: (m['updated_at'] is Timestamp)
          ? (m['updated_at'] as Timestamp).toDate()
          : null,
    );
  }

  /// Empty skeleton for a given date — used when the day has no doc yet.
  factory MealPlanDay.empty(String dateKey) {
    return MealPlanDay(
      dateKey: dateKey,
      slots: { for (final s in MealSlotId.values) s: null },
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'date_key': dateKey,
    };
    for (final slotId in MealSlotId.values) {
      final slot = slots[slotId];
      m[slotId.value] = slot?.toMap();
    }
    return m;
  }
}
