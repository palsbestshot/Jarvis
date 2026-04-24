// Dish — one entry in Rakhi's dish catalog. Used as the source of truth
// for "what can I make" (meal plan slots reference a dish_id, the UI
// renders the dish's name/tags/prep time).
//
// Two sources:
//   - is_custom == false — ships in lib/data/indian_dish_seed.dart and
//     gets seeded into Firestore on first open of Meals section.
//   - is_custom == true  — added by Rakhi herself via the "+ New dish"
//     form or auto-created by the save_meal tool when she mentions a
//     dish not yet in the catalog.

import 'package:cloud_firestore/cloud_firestore.dart';

/// The 5 meal slots Rakhi uses. `breakfast`, `lunch`, `dinner` are the
/// default visible slots; `brunch` and `eveSnacks` are optional extras
/// the day detail only shows when the day has one set or when she taps
/// the "+ Add brunch / eve snacks" button.
///
/// String value (used in Firestore + tool schemas) mirrors the snake-case
/// the Claude tool enums use — never rename these without coordinating
/// with the tool schemas in claude_service.dart.
enum MealSlotId {
  breakfast('breakfast'),
  brunch('brunch'),
  lunch('lunch'),
  eveSnacks('eve_snacks'),
  dinner('dinner');

  final String value;
  const MealSlotId(this.value);

  static MealSlotId? fromValue(String? v) {
    if (v == null) return null;
    for (final s in MealSlotId.values) {
      if (s.value == v) return s;
    }
    return null;
  }

  /// User-facing label ("Eve Snacks" etc.).
  String get label {
    switch (this) {
      case MealSlotId.breakfast:
        return 'Breakfast';
      case MealSlotId.brunch:
        return 'Brunch';
      case MealSlotId.lunch:
        return 'Lunch';
      case MealSlotId.eveSnacks:
        return 'Eve Snacks';
      case MealSlotId.dinner:
        return 'Dinner';
    }
  }

  /// Optional slots start collapsed in the day detail UI.
  bool get isOptional =>
      this == MealSlotId.brunch || this == MealSlotId.eveSnacks;
}

class Dish {
  final String id;
  final String name;
  final String? nameHindi;
  /// Which slots this dish fits. One dish can appear in multiple slots
  /// (e.g. Dal Rice works for both lunch and dinner).
  final List<MealSlotId> mealTypes;
  final int prepMinutes;
  final List<String> tags;
  final List<String> ingredients;
  final String? notes;
  /// Incremented each time the dish is selected for a meal slot — used
  /// to sort the picker so Rakhi's favourites float to the top.
  final int timesUsed;
  /// true = Rakhi added it, false = shipped in the seed.
  final bool isCustom;
  final DateTime? createdAt;
  /// Optional thumbnail URL resolved via DishImageService (Openverse +
  /// Wikipedia fallback) and cached in Firestore. Null = picker renders
  /// the emoji placeholder card.
  final String? imageUrl;

  const Dish({
    required this.id,
    required this.name,
    this.nameHindi,
    required this.mealTypes,
    this.prepMinutes = 20,
    this.tags = const [],
    this.ingredients = const [],
    this.notes,
    this.timesUsed = 0,
    this.isCustom = false,
    this.createdAt,
    this.imageUrl,
  });

  factory Dish.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? <String, dynamic>{};
    return Dish(
      id: doc.id,
      name: (m['name'] ?? '').toString(),
      nameHindi: m['name_hindi']?.toString(),
      mealTypes: ((m['meal_types'] as List?) ?? [])
          .map((v) => MealSlotId.fromValue(v?.toString()))
          .whereType<MealSlotId>()
          .toList(),
      prepMinutes: (m['prep_minutes'] is num)
          ? (m['prep_minutes'] as num).toInt()
          : 20,
      tags: ((m['tags'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      ingredients: ((m['ingredients'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      notes: m['notes']?.toString(),
      timesUsed: (m['times_used'] is num)
          ? (m['times_used'] as num).toInt()
          : 0,
      isCustom: m['is_custom'] == true,
      createdAt: (m['created_at'] is Timestamp)
          ? (m['created_at'] as Timestamp).toDate()
          : null,
      imageUrl: m['image_url']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      if (nameHindi != null && nameHindi!.isNotEmpty) 'name_hindi': nameHindi,
      'meal_types': mealTypes.map((s) => s.value).toList(),
      'prep_minutes': prepMinutes,
      'tags': tags,
      'ingredients': ingredients,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'times_used': timesUsed,
      'is_custom': isCustom,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
    };
  }

  Dish copyWith({
    String? name,
    String? nameHindi,
    List<MealSlotId>? mealTypes,
    int? prepMinutes,
    List<String>? tags,
    List<String>? ingredients,
    String? notes,
    int? timesUsed,
    bool? isCustom,
    String? imageUrl,
  }) {
    return Dish(
      id: id,
      name: name ?? this.name,
      nameHindi: nameHindi ?? this.nameHindi,
      mealTypes: mealTypes ?? this.mealTypes,
      prepMinutes: prepMinutes ?? this.prepMinutes,
      tags: tags ?? this.tags,
      ingredients: ingredients ?? this.ingredients,
      notes: notes ?? this.notes,
      timesUsed: timesUsed ?? this.timesUsed,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
