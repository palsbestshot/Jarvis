// BudgetDoc — Rakhi's monthly finance doc at
// users/rakhi/finance/{yyyy-MM}. Shape mirrors what
// `firestore_service.moveSavings` writes back.
//
//   { budgets: { kitchen: { spent, budget }, ... },
//     jar: { current, goal, goalName, recentAdd: { amount, note, at } } }

class BudgetCategory {
  final String id;
  final String label;
  final int spent;
  final int budget;

  const BudgetCategory({
    required this.id,
    required this.label,
    required this.spent,
    required this.budget,
  });

  double get progress => budget <= 0 ? 0 : (spent / budget).clamp(0.0, 1.0);
  bool get warn => progress > 0.85 && progress < 1.0;
  bool get over => spent > budget;

  factory BudgetCategory.fromMap(
    String id,
    String label,
    Map<String, dynamic>? m,
  ) {
    final spent = (m?['spent'] is num) ? (m!['spent'] as num).toInt() : 0;
    final budget = (m?['budget'] is num) ? (m!['budget'] as num).toInt() : 0;
    return BudgetCategory(
      id: id,
      label: label,
      spent: spent,
      budget: budget,
    );
  }
}

class JarState {
  final int current;
  final int goal;
  final String goalName;
  final int? recentAddAmount;
  final String? recentAddNote;

  const JarState({
    required this.current,
    required this.goal,
    required this.goalName,
    this.recentAddAmount,
    this.recentAddNote,
  });

  double get progress => goal <= 0 ? 0 : (current / goal).clamp(0.0, 1.0);

  factory JarState.fromMap(Map<String, dynamic>? m) {
    if (m == null) {
      return const JarState(current: 0, goal: 25000, goalName: 'Own money');
    }
    final current = (m['current'] is num) ? (m['current'] as num).toInt() : 0;
    final goal = (m['goal'] is num) ? (m['goal'] as num).toInt() : 25000;
    final goalName = (m['goalName'] ?? 'Own money').toString();
    final recent = (m['recentAdd'] as Map?)?.cast<String, dynamic>();
    return JarState(
      current: current,
      goal: goal,
      goalName: goalName,
      recentAddAmount:
          (recent?['amount'] is num) ? (recent!['amount'] as num).toInt() : null,
      recentAddNote: recent?['note']?.toString(),
    );
  }
}

class BudgetDoc {
  final JarState jar;
  final List<BudgetCategory> categories;

  const BudgetDoc({required this.jar, required this.categories});

  /// Default category order — matches the Rakhi Finance section design.
  static const List<List<String>> defaultCategoryOrder = [
    ['kitchen', 'Kitchen'],
    ['kabir', 'Kabir'],
    ['home', 'Home'],
    ['personal', 'Personal'],
  ];

  factory BudgetDoc.fromMap(Map<String, dynamic>? m) {
    final budgets =
        (m?['budgets'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final cats = defaultCategoryOrder.map((entry) {
      final id = entry[0];
      final label = entry[1];
      return BudgetCategory.fromMap(
        id,
        label,
        (budgets[id] as Map?)?.cast<String, dynamic>(),
      );
    }).toList();
    return BudgetDoc(
      jar: JarState.fromMap((m?['jar'] as Map?)?.cast<String, dynamic>()),
      categories: cats,
    );
  }

  /// Fallback when the doc doesn't exist yet — seed reasonable numbers so the
  /// Finance screen isn't blank on first open.
  factory BudgetDoc.empty() {
    return BudgetDoc(
      jar: const JarState(current: 0, goal: 25000, goalName: 'Own money'),
      categories: defaultCategoryOrder.map((e) {
        return BudgetCategory(id: e[0], label: e[1], spent: 0, budget: 0);
      }).toList(),
    );
  }
}
