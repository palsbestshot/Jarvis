import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Finance.fromMap(Map<String, dynamic> data, String id, String userId) {
    final raw = data['date'];
    DateTime date;
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is String) {
      date = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      final updated = data['updated_at'];
      date = updated is Timestamp ? updated.toDate() : DateTime.now();
    }
    return Finance(
      id: id,
      category: (data['category'] as String?) ?? 'Savings',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      date: date,
      description: (data['description'] as String?) ??
          (data['title'] as String?) ??
          '',
      userId: userId,
    );
  }
}
