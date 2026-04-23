// NutritionSheet — bottom sheet rendered on top of MealDayDetailScreen
// when Rakhi taps "Show nutrition". Collects the day's planned meals +
// their dish catalog entries, fires ClaudeService.computeDayNutrition,
// and renders:
//
//   - 3 per-person cards (Rakhi · Pallav · Palkhi) with kcal targets +
//     today's tally
//   - Per-meal breakdown cards (slot + dish + grams + kcal + macros)
//   - Caveat line ("approx ±10-15%")
//
// Numbers are computed every tap (no caching) — ~500-900ms round-trip.
// If Rakhi changes a slot and re-opens, the fresh plan flows through
// and gets re-costed.
//
// On Claude failure: shows a friendly retry button. On no-meals-planned:
// shows an empty-state nudge to add dishes first.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/dish.dart';
import '../../models/meal_plan_day.dart';
import '../../models/user_profile.dart';
import '../../services/claude_service.dart';

/// Typical daily kcal targets for each household member. Used as the
/// "target" bar on the per-person card so Rakhi can eyeball today's
/// tally vs the goal. Purely illustrative — real needs vary with
/// activity level + health goals.
const int kRakhiKcalTarget = 2000;
const int kPallavKcalTarget = 2400;
const int kPalkhiKcalTarget = 1100;

class NutritionSheet extends StatefulWidget {
  final UserProfile user;
  final DateTime date;
  final MealPlanDay plan;

  /// The dish objects already resolved from dish_catalog by the parent
  /// day detail screen — avoids a second round-trip and works with the
  /// parent's cache.
  final Map<String, Dish?> dishById;

  const NutritionSheet({
    super.key,
    required this.user,
    required this.date,
    required this.plan,
    required this.dishById,
  });

  @override
  State<NutritionSheet> createState() => _NutritionSheetState();
}

class _NutritionSheetState extends State<NutritionSheet> {
  final _claude = ClaudeService();
  bool _loading = true;
  Map<String, dynamic>? _nutrition;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Gather planned slots into the shape computeDayNutrition expects.
    // We only include slots that have a dish_id AND a resolved Dish in
    // the parent's cache — skipping empty / broken slots silently.
    final meals = <Map<String, dynamic>>[];
    for (final slotId in MealSlotId.values) {
      final slot = widget.plan.slot(slotId);
      if (slot == null || slot.dishId.isEmpty) continue;
      final dish = widget.dishById[slot.dishId];
      if (dish == null) continue;
      meals.add({
        'slot': slotId.value,
        'slot_label': slotId.label,
        'dish_name': dish.name,
        'prep_minutes': dish.prepMinutes,
        'ingredients': dish.ingredients,
        'tags': dish.tags,
        if (slot.notes != null && slot.notes!.isNotEmpty) 'notes': slot.notes,
      });
    }

    if (meals.isEmpty) {
      setState(() {
        _loading = false;
        _nutrition = null;
        _error = 'empty';
      });
      return;
    }

    try {
      final dateLabel =
          DateFormat('EEEE, d MMMM y').format(widget.date);
      final result = await _claude.computeDayNutrition(
        dateLabel: dateLabel,
        meals: meals,
      );
      if (!mounted) return;
      if (result.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'claude_failed';
        });
        return;
      }
      setState(() {
        _loading = false;
        _nutrition = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'exception: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.user.accentColor;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: JarvisTheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(JarvisTheme.large),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: JarvisTheme.sm),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JarvisTheme.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: JarvisTheme.sm),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: JarvisTheme.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.local_fire_department,
                        color: accent, size: 24),
                    const SizedBox(width: JarvisTheme.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nutrition',
                            style: JarvisTheme.headingMedium,
                          ),
                          Text(
                            DateFormat('EEEE, d MMMM')
                                .format(widget.date),
                            style: JarvisTheme.bodySmall.copyWith(
                              color: JarvisTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Re-compute',
                      icon: Icon(Icons.refresh,
                          color: JarvisTheme.textMuted),
                      onPressed: _loading ? null : _compute,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _buildBody(accent, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(Color accent, ScrollController controller) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
            const SizedBox(height: JarvisTheme.md),
            Text(
              'Jarvis is counting calories…',
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (_error == 'empty') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(JarvisTheme.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_menu,
                  size: 48, color: JarvisTheme.textMuted),
              const SizedBox(height: JarvisTheme.sm),
              Text(
                'No meals planned for this day yet.',
                style: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: JarvisTheme.xs),
              Text(
                'Add breakfast / lunch / dinner to see nutrition.',
                style: JarvisTheme.bodySmall
                    .copyWith(color: JarvisTheme.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _nutrition == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(JarvisTheme.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  size: 40, color: JarvisTheme.textMuted),
              const SizedBox(height: JarvisTheme.sm),
              Text(
                "Couldn't reach Jarvis right now.",
                style: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textSecondary),
              ),
              const SizedBox(height: JarvisTheme.sm),
              ElevatedButton.icon(
                onPressed: _compute,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final data = _nutrition!;
    final totals = (data['household_totals'] as Map<String, dynamic>?) ?? {};
    final meals = (data['meals'] as List?) ?? const [];
    final caveat = (data['caveat'] ?? 'approximate ±10-15%').toString();

    final rakhiKcal = _intOf(totals['rakhi_kcal']);
    final pallavKcal = _intOf(totals['pallav_kcal']);
    final palkhiKcal = _intOf(totals['palkhi_kcal']);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(JarvisTheme.md),
      children: [
        // Per-person cards row
        Row(
          children: [
            Expanded(
              child: _personCard(
                name: 'Rakhi',
                kcal: rakhiKcal,
                target: kRakhiKcalTarget,
                accent: accent,
                emoji: '🌸',
              ),
            ),
            const SizedBox(width: JarvisTheme.xs),
            Expanded(
              child: _personCard(
                name: 'Pallav',
                kcal: pallavKcal,
                target: kPallavKcalTarget,
                accent: accent,
                emoji: '🧑',
              ),
            ),
            const SizedBox(width: JarvisTheme.xs),
            Expanded(
              child: _personCard(
                name: 'Palkhi',
                kcal: palkhiKcal,
                target: kPalkhiKcalTarget,
                accent: accent,
                emoji: '👶',
                subtitle: 'toddler',
              ),
            ),
          ],
        ),
        const SizedBox(height: JarvisTheme.md),
        Text(
          'Meal breakdown',
          style: JarvisTheme.bodySmall.copyWith(
            color: JarvisTheme.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: JarvisTheme.xs),
        for (final m in meals)
          if (m is Map<String, dynamic>) _mealCard(m, accent),
        const SizedBox(height: JarvisTheme.md),
        Container(
          padding: const EdgeInsets.all(JarvisTheme.sm),
          decoration: BoxDecoration(
            color: JarvisTheme.surface2,
            borderRadius: BorderRadius.circular(JarvisTheme.small),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: JarvisTheme.textMuted),
              const SizedBox(width: JarvisTheme.xs),
              Expanded(
                child: Text(
                  caveat,
                  style: JarvisTheme.bodySmall.copyWith(
                    color: JarvisTheme.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: JarvisTheme.md),
      ],
    );
  }

  Widget _personCard({
    required String name,
    required int kcal,
    required int target,
    required Color accent,
    required String emoji,
    String? subtitle,
  }) {
    final pct = (target == 0) ? 0.0 : (kcal / target).clamp(0.0, 1.3);
    final overTarget = pct > 1.0;
    return Container(
      padding: const EdgeInsets.all(JarvisTheme.sm),
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: BorderRadius.circular(JarvisTheme.small),
        border: Border.all(
          color: accent.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  name,
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: JarvisTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
                fontSize: 10,
              ),
            ),
          const SizedBox(height: JarvisTheme.xs),
          Text(
            '$kcal',
            style: JarvisTheme.headingMedium.copyWith(
              color: overTarget ? Colors.orange : accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'of $target kcal',
            style: JarvisTheme.bodySmall.copyWith(
              color: JarvisTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: JarvisTheme.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: JarvisTheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                overTarget ? Colors.orange : accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealCard(Map<String, dynamic> m, Color accent) {
    final slotLabel = (m['slot_label'] ?? m['slot'] ?? '').toString();
    final dishName = (m['dish_name'] ?? '').toString();
    final servingNote = (m['serving_note'] ?? '').toString();
    final portionG = _intOf(m['adult_portion_g']);
    final kcal = _intOf(m['kcal_per_adult_serving']);
    final carbs = _intOf(m['carbs_g']);
    final protein = _intOf(m['protein_g']);
    final fat = _intOf(m['fat_g']);

    return Container(
      margin: const EdgeInsets.only(bottom: JarvisTheme.xs),
      padding: const EdgeInsets.all(JarvisTheme.sm),
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: BorderRadius.circular(JarvisTheme.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  slotLabel.toUpperCase(),
                  style: JarvisTheme.bodySmall.copyWith(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: JarvisTheme.xs),
              Expanded(
                child: Text(
                  dishName,
                  style: JarvisTheme.bodyLarge.copyWith(
                    color: JarvisTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$kcal kcal',
                style: JarvisTheme.bodyMedium.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (servingNote.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '${portionG}g · $servingNote',
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
              ),
            ),
          ] else if (portionG > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${portionG}g per adult serving',
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
              ),
            ),
          ],
          const SizedBox(height: JarvisTheme.xs),
          Row(
            children: [
              _macroPill('Carbs', '${carbs}g'),
              const SizedBox(width: JarvisTheme.xs),
              _macroPill('Protein', '${protein}g'),
              const SizedBox(width: JarvisTheme.xs),
              _macroPill('Fat', '${fat}g'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(JarvisTheme.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: JarvisTheme.bodySmall.copyWith(
              color: JarvisTheme.textMuted,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: JarvisTheme.bodySmall.copyWith(
              color: JarvisTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  int _intOf(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
