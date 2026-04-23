// Meal model (Rakhi only) - to be implemented in Phase 2
class Meal {
  final String id;
  final String name;
  final DateTime date;
  final String mealType; // breakfast, lunch, dinner, snack
  final int calories;
  final String notes;
  final String userId;

  const Meal({
    required this.id,
    required this.name,
    required this.date,
    required this.mealType,
    required this.calories,
    required this.notes,
    required this.userId,
  });
}