// MealDayDetailScreen — full-screen view of a single day's meal plan.
// Shows breakfast/lunch/dinner by default; brunch + eve_snacks are
// hidden behind "+ Add brunch" / "+ Add eve snacks" pills unless the
// day has one planned.
//
// Tap `+ Add <slot>` or the overflow "Change" → opens DishPickerSheet.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/dish.dart';
import '../../models/meal_plan_day.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import 'dish_picker_sheet.dart';
import 'nutrition_sheet.dart';

class MealDayDetailScreen extends StatefulWidget {
  final UserProfile user;
  final DateTime date;

  const MealDayDetailScreen({
    super.key,
    required this.user,
    required this.date,
  });

  @override
  State<MealDayDetailScreen> createState() => _MealDayDetailScreenState();
}

class _MealDayDetailScreenState extends State<MealDayDetailScreen> {
  final _firestore = FirestoreService();
  // Locally-toggled "show optional slot" state so Rakhi can open the
  // brunch / eve snacks rows even when no plan exists yet.
  bool _showBrunch = false;
  bool _showEveSnacks = false;

  String get _dateKey {
    final d = widget.date;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _pickDishFor(MealSlotId slot, MealSlot? existing) async {
    final picked = await showModalBottomSheet<DishPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishPickerSheet(
        user: widget.user,
        slot: slot,
        currentDishId: existing?.dishId,
      ),
    );
    if (picked == null || !mounted) return;
    // Save the slot, then bump the dish's usage counter.
    await _firestore.setMealSlot(
      widget.user.id,
      _dateKey,
      slot.value,
      MealSlot(dishId: picked.dishId, notes: picked.notes).toMap(),
    );
    await _firestore.incrementDishTimesUsed(widget.user.id, picked.dishId);
  }

  Future<void> _clearSlot(MealSlotId slot) async {
    await _firestore.setMealSlot(widget.user.id, _dateKey, slot.value, null);
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('EEEE, d MMM y').format(widget.date);
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      appBar: AppBar(
        backgroundColor: JarvisTheme.background,
        elevation: 0,
        title: Text(dayLabel, style: JarvisTheme.headingMedium),
        iconTheme: IconThemeData(color: JarvisTheme.textPrimary),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore.mealPlanDayStream(widget.user.id, _dateKey),
        builder: (context, snapshot) {
          MealPlanDay plan;
          if (snapshot.hasData && snapshot.data!.exists) {
            plan = MealPlanDay.fromDoc(snapshot.data!);
          } else {
            plan = MealPlanDay.empty(_dateKey);
          }
          // Auto-show optional rows if they're already planned.
          final brunchPlanned = plan.slot(MealSlotId.brunch) != null;
          final eveSnacksPlanned = plan.slot(MealSlotId.eveSnacks) != null;
          // Only show the nutrition button when at least one slot has a
          // dish planned — nothing to compute otherwise. Keeps the header
          // uncluttered on empty days.
          final hasAnyPlanned = MealSlotId.values.any((s) {
            final v = plan.slot(s);
            return v != null && v.dishId.isNotEmpty;
          });
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              JarvisTheme.md,
              JarvisTheme.sm,
              JarvisTheme.md,
              JarvisTheme.xxl,
            ),
            children: [
              if (hasAnyPlanned) ...[
                _buildNutritionButton(plan),
                const SizedBox(height: JarvisTheme.sm),
              ],
              _slotCard(plan, MealSlotId.breakfast),
              if (_showBrunch || brunchPlanned)
                _slotCard(plan, MealSlotId.brunch)
              else
                _addOptionalButton(MealSlotId.brunch,
                    onPressed: () => setState(() => _showBrunch = true)),
              _slotCard(plan, MealSlotId.lunch),
              if (_showEveSnacks || eveSnacksPlanned)
                _slotCard(plan, MealSlotId.eveSnacks)
              else
                _addOptionalButton(MealSlotId.eveSnacks,
                    onPressed: () =>
                        setState(() => _showEveSnacks = true)),
              _slotCard(plan, MealSlotId.dinner),
            ],
          );
        },
      ),
    );
  }

  /// Full-width pill at the top of the day-detail ListView. Tapping opens
  /// `NutritionSheet`, which gathers the planned slots + their dish entries
  /// (via the parent `_dishCache`) and hits Claude for a live calorie +
  /// macro breakdown. Only rendered when at least one slot is planned.
  Widget _buildNutritionButton(MealPlanDay plan) {
    return OutlinedButton.icon(
      onPressed: () => _openNutritionSheet(plan),
      icon: Icon(Icons.local_fire_department,
          color: widget.user.accentColor, size: 20),
      label: Text(
        'Show nutrition',
        style: TextStyle(
          color: widget.user.accentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: widget.user.accentColor.withOpacity(0.5),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JarvisTheme.small),
        ),
      ),
    );
  }

  /// Ensure every planned dish is in `_dishCache`, then open the sheet.
  /// Pre-warming means the sheet's computeDayNutrition call has the dish
  /// names + ingredients + tags already; no extra round-trip inside the
  /// sheet itself.
  Future<void> _openNutritionSheet(MealPlanDay plan) async {
    final plannedIds = <String>[
      for (final s in MealSlotId.values)
        if (plan.slot(s) != null && plan.slot(s)!.dishId.isNotEmpty)
          plan.slot(s)!.dishId,
    ];
    // Load any dishes we haven't cached yet.
    await Future.wait(
      plannedIds
          .where((id) => !_dishCache.containsKey(id))
          .map((id) => _loadDish(id)),
    );
    if (!mounted) return;

    final dishById = <String, Dish?>{
      for (final id in plannedIds) id: _dishCache[id],
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NutritionSheet(
        user: widget.user,
        date: widget.date,
        plan: plan,
        dishById: dishById,
      ),
    );
  }

  Widget _addOptionalButton(MealSlotId slot,
      {required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JarvisTheme.xs),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Text('Add ${slot.label.toLowerCase()}'),
        style: OutlinedButton.styleFrom(
          foregroundColor: JarvisTheme.textSecondary,
          side: BorderSide(color: JarvisTheme.surface2, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JarvisTheme.small),
          ),
          padding: const EdgeInsets.symmetric(
            vertical: JarvisTheme.sm,
            horizontal: JarvisTheme.md,
          ),
        ),
      ),
    );
  }

  Widget _slotCard(MealPlanDay plan, MealSlotId slot) {
    final slotValue = plan.slot(slot);
    final isPlanned = slotValue != null && slotValue.dishId.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: JarvisTheme.xs),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(JarvisTheme.medium),
        border: Border.all(
          color: JarvisTheme.surface2,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JarvisTheme.md),
        child: isPlanned
            ? _plannedSlotBody(plan, slot, slotValue)
            : _emptySlotBody(slot),
      ),
    );
  }

  Widget _emptySlotBody(MealSlotId slot) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(slot.label,
                  style: JarvisTheme.bodySmall.copyWith(
                    color: JarvisTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  )),
              const SizedBox(height: JarvisTheme.xs),
              Text(
                'Not planned',
                style: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textSecondary),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => _pickDishFor(slot, null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          style: TextButton.styleFrom(
            foregroundColor: widget.user.accentColor,
          ),
        ),
      ],
    );
  }

  Widget _plannedSlotBody(
      MealPlanDay plan, MealSlotId slot, MealSlot value) {
    return FutureBuilder<Dish?>(
      future: _loadDish(value.dishId),
      builder: (context, snap) {
        final dish = snap.data;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label,
                      style: JarvisTheme.bodySmall.copyWith(
                        color: JarvisTheme.textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      )),
                  const SizedBox(height: JarvisTheme.xs),
                  Text(
                    dish?.name ?? '(dish removed)',
                    style: JarvisTheme.bodyLarge.copyWith(
                      color: JarvisTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (dish != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${dish.prepMinutes} min • ${dish.tags.take(3).join(" · ")}',
                      style: JarvisTheme.bodySmall
                          .copyWith(color: JarvisTheme.textMuted),
                    ),
                  ],
                  if (value.notes != null && value.notes!.isNotEmpty) ...[
                    const SizedBox(height: JarvisTheme.xs),
                    Text(
                      value.notes!,
                      style: JarvisTheme.bodySmall.copyWith(
                        color: JarvisTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: JarvisTheme.textMuted),
              color: JarvisTheme.surface2,
              onSelected: (action) async {
                if (action == 'change') {
                  await _pickDishFor(slot, value);
                } else if (action == 'clear') {
                  await _clearSlot(slot);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'change',
                  child: Text('Change dish',
                      style: TextStyle(color: JarvisTheme.textPrimary)),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear',
                      style: TextStyle(color: JarvisTheme.textPrimary)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // Simple dish lookup cache to avoid re-reading every rebuild. Keyed
  // by dishId; MealDayDetailScreen lifetime is short so no need to
  // invalidate.
  final Map<String, Dish?> _dishCache = {};
  Future<Dish?> _loadDish(String dishId) async {
    if (_dishCache.containsKey(dishId)) return _dishCache[dishId];
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.id)
          .collection('dish_catalog')
          .doc(dishId)
          .get();
      if (!doc.exists) {
        _dishCache[dishId] = null;
        return null;
      }
      final dish = Dish.fromDoc(doc);
      _dishCache[dishId] = dish;
      return dish;
    } catch (_) {
      _dishCache[dishId] = null;
      return null;
    }
  }
}

