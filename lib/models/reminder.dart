// Reminder model - to be implemented in Phase 2
class Reminder {
  final String id;
  final String title;
  final DateTime time;
  final bool recurring;
  final String recurrencePattern;
  final bool enabled;
  final String userId;

  const Reminder({
    required this.id,
    required this.title,
    required this.time,
    required this.recurring,
    required this.recurrencePattern,
    required this.enabled,
    required this.userId,
  });
}