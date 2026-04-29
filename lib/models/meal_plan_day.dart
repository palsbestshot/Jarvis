// MealPlanDay — one doc at users/{uid}/meal_plans/{yyyy-mm-dd}.
// Holds up to 5 meal slots for a single calendar day. Each slot is a
// LIST of dishes (e.g. dal + chawal + roti + sabzi + salad for one
// lunch). The calendar view shows a month of these at a glance; tapping
// a day opens MealDayDetail.
//
// Storage shape (Firestore):
//   {
//     date_key: '2026-04-29',
//     lunch:    [{ dish_id, notes? }, { dish_id, notes? }, ...],
//     dinner:   [...],
//     ...
//   }
//
// Legacy back-compat: older docs stored each slot as a SINGLE object
// `{dish_id, notes}` instead of a list. The reader transparently treats
// such a value as a 1-element list. Any subsequent write on the slot
// upgrades it to the list shape; no migration job needed.

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
  /// Keyed by slot. Empty list means "not planned"; one or more dishes
  /// means Rakhi has set this slot.
  final Map<MealSlotId, List<MealSlot>> slots;
  final DateTime? updatedAt;

  const MealPlanDay({
    required this.dateKey,
    required this.slots,
    this.updatedAt,
  });

  /// All dishes planned for the slot (empty = not planned).
  List<MealSlot> dishes(MealSlotId id) => slots[id] ?? const <MealSlot>[];

  /// Convenience for callsites that just care whether anything is planned.
  bool isPlanned(MealSlotId id) => dishes(id).isNotEmpty;

  /// True if the day has any slot planned — used by the calendar view to
  /// decide whether to draw the dots under the date number.
  bool get hasAnyPlanned => slots.values.any((v) => v.isNotEmpty);

  /// How many of the 5 slots are planned. The calendar uses this for
  /// a subtle progress indicator on day cells.
  int get plannedCount => slots.values.where((v) => v.isNotEmpty).length;

  /// Total dish count across every slot — useful when showing "5 dishes
  /// across 3 slots" type summaries.
  int get totalDishCount =>
      slots.values.fold<int>(0, (sum, list) => sum + list.length);

  factory MealPlanDay.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? <String, dynamic>{};
    return MealPlanDay(
      dateKey: (m['date_key'] ?? doc.id).toString(),
      slots: _parseSlots(m),
      updatedAt: (m['updated_at'] is Timestamp)
          ? (m['updated_at'] as Timestamp).toDate()
          : null,
    );
  }

  /// Build a MealPlanDay from a plain map — used when streaming a query
  /// result that's already been flattened to Map<String, dynamic>.
  factory MealPlanDay.fromMap(String dateKey, Map<String, dynamic> m) {
    return MealPlanDay(dateKey: dateKey, slots: _parseSlots(m));
  }

  /// Empty skeleton for a given date — used when the day has no doc yet.
  factory MealPlanDay.empty(String dateKey) {
    return MealPlanDay(
      dateKey: dateKey,
      slots: { for (final s in MealSlotId.values) s: const <MealSlot>[] },
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'date_key': dateKey,
    };
    for (final slotId in MealSlotId.values) {
      final list = slots[slotId] ?? const <MealSlot>[];
      m[slotId.value] = list.isEmpty
          ? null
          : list.map((s) => s.toMap()).toList();
    }
    return m;
  }

  /// Parse the slot fields from a raw Firestore map into the typed
  /// `Map<MealSlotId, List<MealSlot>>` shape, accepting both the new
  /// list-of-dishes shape AND the legacy single-object shape.
  static Map<MealSlotId, List<MealSlot>> _parseSlots(Map<String, dynamic> m) {
    final slots = <MealSlotId, List<MealSlot>>{};
    for (final slotId in MealSlotId.values) {
      slots[slotId] = _parseSlotValue(m[slotId.value]);
    }
    return slots;
  }

  /// Coerce one slot field into a list. Accepts:
  ///   - `List` of maps → new shape, parse each.
  ///   - `Map` (single dish) → legacy shape, wrap as 1-element list.
  ///   - anything else (null, missing field, garbage) → empty list.
  static List<MealSlot> _parseSlotValue(dynamic raw) {
    if (raw is List) {
      final out = <MealSlot>[];
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          try {
            final slot = MealSlot.fromMap(entry);
            if (slot.dishId.isNotEmpty) out.add(slot);
          } catch (_) {/* skip malformed entry */}
        }
      }
      return out;
    }
    if (raw is Map<String, dynamic>) {
      try {
        final slot = MealSlot.fromMap(raw);
        if (slot.dishId.isNotEmpty) return [slot];
      } catch (_) {/* fall through */}
    }
    return const <MealSlot>[];
  }
}
