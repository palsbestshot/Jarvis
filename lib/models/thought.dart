// Thought model - to be implemented in Phase 2
class Thought {
  final String id;
  final String content;
  final DateTime timestamp;
  final String userId;

  const Thought({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.userId,
  });
}