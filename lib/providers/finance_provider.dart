// Streams Pallav's finance entries from users/{userId}/finance.
// Each doc is { category, amount, date, description, updated_at }.
// The derived net-worth snapshot groups entries by category so the hero
// card can show allocation bars + sparkline without a second Firestore read.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../models/finance.dart';

final financeEntriesProvider =
    StreamProvider.family<List<Finance>, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .doc(userId)
      .collection(AppConstants.financeCollection)
      .orderBy('date', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => Finance.fromMap(d.data(), d.id, userId))
          .toList());
});

class AllocationBucket {
  final String category;
  final double amount;
  final double percent;

  const AllocationBucket({
    required this.category,
    required this.amount,
    required this.percent,
  });
}

class NetWorthSnapshot {
  final double total;
  final List<AllocationBucket> allocation;
  final List<double> sparkline;
  final double deltaPct;

  const NetWorthSnapshot({
    required this.total,
    required this.allocation,
    required this.sparkline,
    required this.deltaPct,
  });
}

final netWorthSnapshotProvider =
    Provider.family<NetWorthSnapshot, String>((ref, userId) {
  final async = ref.watch(financeEntriesProvider(userId));
  final entries = async.valueOrNull ?? const <Finance>[];
  if (entries.isEmpty) {
    return const NetWorthSnapshot(
      total: 0,
      allocation: [],
      sparkline: [0, 0, 0, 0, 0, 0],
      deltaPct: 0,
    );
  }

  final byCategory = <String, double>{};
  for (final e in entries) {
    byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
  }
  final total = byCategory.values.fold<double>(0, (a, b) => a + b);
  final allocation = byCategory.entries
      .map((e) => AllocationBucket(
            category: e.key,
            amount: e.value,
            percent: total == 0 ? 0 : (e.value / total) * 100,
          ))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final now = DateTime.now();
  final months = List.generate(6, (i) {
    final m = DateTime(now.year, now.month - (5 - i), 1);
    final next = DateTime(m.year, m.month + 1, 1);
    return entries
        .where((e) => !e.date.isBefore(m) && e.date.isBefore(next))
        .fold<double>(0, (a, e) => a + e.amount);
  });

  final cum = <double>[];
  double running = 0;
  for (final m in months) {
    running += m;
    cum.add(running);
  }
  final sparkline = cum.isEmpty ? [0.0] : cum;

  final deltaPct = sparkline.length >= 2 && sparkline[sparkline.length - 2] > 0
      ? ((sparkline.last - sparkline[sparkline.length - 2]) /
              sparkline[sparkline.length - 2]) *
          100
      : 0.0;

  return NetWorthSnapshot(
    total: total,
    allocation: allocation,
    sparkline: sparkline,
    deltaPct: deltaPct,
  );
});
