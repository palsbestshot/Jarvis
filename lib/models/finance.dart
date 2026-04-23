// Finance model (Pallav only) - to be implemented in Phase 2
class Finance {
  final String id;
  final String category;
  final double amount;
  final DateTime date;
  final String description;
  final String userId;

  const Finance({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    required this.description,
    required this.userId,
  });
}