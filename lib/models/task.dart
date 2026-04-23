// Task model - to be implemented in Phase 2
class Task {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final bool completed;
  final String userId;

  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.completed,
    required this.userId,
  });
}