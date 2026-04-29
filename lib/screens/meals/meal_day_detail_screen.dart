// MealDayDetailScreen — full-screen view of a single day's meal plan.
// Each slot can hold multiple dishes (e.g. dal + chawal + roti + sabzi
// + salad for lunch). Breakfast / lunch / dinner show by default;
// brunch + eve_snacks are hidden behind "+ Add brunch" / "+ Add eve
// snacks" pills unless the day has them planned.
//
// Tapping "+ Add dish" inside a slot, or the row's tap-to-change,
// opens DishPickerSheet. The picker is single-pick per add: tap one,
// it lands as a new row, tap "+" again for the next dish. (Faster
// learning curve than a multi-select sheet for a 5-component thali.)
//
// Styling is PWA-aware via kIsWeb: on web (rakhi-web PWA) cards get
// soft pink shadows, an InstrumentSerif dish-name treatment in the
// rakhiAccentDeep colour, and uppercase DMSans slot labels. On
// Android the same widgets fall back to the Pallav-app surface
// styling.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// Append a new dish to the slot's list. Used by the empty-state
  /// "Add" button and the per-slot "+ Add another dish" button.
  Future<void> _addDishTo(MealSlotId slot) async {
    final picked = await showModalBottomSheet<DishPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishPickerSheet(
        user: widget.user,
        slot: slot,
        currentDishId: null,
      ),
    );
    if (picked == null || !mounted) return;
    await _firestore.appendDishToMealSlot(
      widget.user.id,
      _dateKey,
      slot.value,
      MealSlot(dishId: picked.dishId, notes: picked.notes).toMap(),
    );
    await _firestore.incrementDishTimesUsed(widget.user.id, picked.dishId);
  }

  /// Replace one specific dish in the slot — opens the picker pre-
  /// selected on the existing dish so changing it is one tap.
  Future<void> _changeDishAt(
    MealSlotId slot,
    int index,
    List<MealSlot> current,
  ) async {
    final existing = current[index];
    final picked = await showModalBottomSheet<DishPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DishPickerSheet(
        user: widget.user,
        slot: slot,
        currentDishId: existing.dishId,
      ),
    );
    if (picked == null || !mounted) return;
    final updated = [...current];
    updated[index] = MealSlot(dishId: picked.dishId, notes: picked.notes);
    await _firestore.setMealSlot(
      widget.user.id,
      _dateKey,
      slot.value,
      updated.map((s) => s.toMap()).toList(),
    );
    await _firestore.incrementDishTimesUsed(widget.user.id, picked.dishId);
  }

  /// Remove just one dish row from the slot.
  Future<void> _removeDishAt(
    MealSlotId slot,
    int index,
    List<MealSlot> current,
  ) async {
    final updated = [...current]..removeAt(index);
    await _firestore.setMealSlot(
      widget.user.id,
      _dateKey,
      slot.value,
      updated.isEmpty ? null : updated.map((s) => s.toMap()).toList(),
    );
  }

  /// Wipe the entire slot — exposed via the slot-level overflow menu.
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
          final brunchPlanned = plan.isPlanned(MealSlotId.brunch);
          final eveSnacksPlanned = plan.isPlanned(MealSlotId.eveSnacks);
          // Only show the nutrition button when at least one slot has a
          // dish — nothing to compute otherwise.
          final hasAnyPlanned = plan.hasAnyPlanned;
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

  /// Full-width pill at the top of the day-detail ListView. Tapping
  /// opens `NutritionSheet`, which gathers every dish across every
  /// planned slot and hits Claude for a live calorie + macro breakdown.
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

  /// Ensure every planned dish (across every slot) is in `_dishCache`,
  /// then open the sheet. Pre-warming means the sheet's
  /// computeDayNutrition call has names + ingredients + tags ready.
  Future<void> _openNutritionSheet(MealPlanDay plan) async {
    final plannedIds = <String>[
      for (final s in MealSlotId.values)
        for (final m in plan.dishes(s))
          if (m.dishId.isNotEmpty) m.dishId,
    ];
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
    final dishes = plan.dishes(slot);
    final isPlanned = dishes.isNotEmpty;
    final Color cardBg;
    final Color borderColor;
    final List<BoxShadow>? shadow;
    final double radius;
    if (kIsWeb) {
      radius = 14;
      if (isPlanned) {
        cardBg = Colors.white;
        borderColor = JarvisTheme.surface2;
        shadow = [
          BoxShadow(
            color: const Color(0xFFF9D6E2).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
      } else {
        cardBg = JarvisTheme.surface2;
        borderColor = JarvisTheme.surface3;
        shadow = null;
      }
    } else {
      radius = JarvisTheme.medium.toDouble();
      cardBg = JarvisTheme.surface;
      borderColor = JarvisTheme.surface2;
      shadow = null;
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: JarvisTheme.xs),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(JarvisTheme.md),
        child: isPlanned
            ? _plannedSlotBody(slot, dishes)
            : _emptySlotBody(slot),
      ),
    );
  }

  Widget _emptySlotBody(MealSlotId slot) {
    final labelStyle = kIsWeb
        ? TextStyle(
            fontFamily: 'DMSans',
            fontSize: 10,
            color: widget.user.accentColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          )
        : JarvisTheme.bodySmall.copyWith(
            color: JarvisTheme.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          );
    final labelText = kIsWeb ? slot.label.toUpperCase() : slot.label;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labelText, style: labelStyle),
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
          onPressed: () => _addDishTo(slot),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          style: TextButton.styleFrom(
            foregroundColor: widget.user.accentColor,
          ),
        ),
      ],
    );
  }

  Widget _plannedSlotBody(MealSlotId slot, List<MealSlot> dishes) {
    final labelStyle = kIsWeb
        ? TextStyle(
            fontFamily: 'DMSans',
            fontSize: 10,
            color: widget.user.accentColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          )
        : JarvisTheme.bodySmall.copyWith(
            color: JarvisTheme.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          );
    final labelText = kIsWeb ? slot.label.toUpperCase() : slot.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Slot header row: label + slot-level overflow menu.
        Row(
          children: [
            Expanded(
              child: Text(labelText, style: labelStyle),
            ),
            if (dishes.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${dishes.length} dishes',
                  style: JarvisTheme.bodySmall.copyWith(
                    color: JarvisTheme.textMuted,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: JarvisTheme.textMuted),
              color: JarvisTheme.surface2,
              onSelected: (action) async {
                if (action == 'clear_all') await _clearSlot(slot);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'clear_all',
                  child: Text('Clear all',
                      style: TextStyle(color: JarvisTheme.textPrimary)),
                ),
              ],
            ),
          ],
        ),
        // Dish rows.
        for (int i = 0; i < dishes.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: JarvisTheme.surface2,
            ),
          _dishRow(slot, dishes, i),
        ],
        // Footer "+ add another dish" button.
        const SizedBox(height: JarvisTheme.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addDishTo(slot),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another dish'),
            style: TextButton.styleFrom(
              foregroundColor: widget.user.accentColor,
              padding: const EdgeInsets.symmetric(
                horizontal: JarvisTheme.sm,
                vertical: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dishRow(MealSlotId slot, List<MealSlot> dishes, int index) {
    final dish = dishes[index];
    final dishNameStyle = kIsWeb
        ? const TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 20,
            color: JarvisTheme.rakhiAccentDeep,
            fontWeight: FontWeight.w400,
          )
        : JarvisTheme.bodyLarge.copyWith(
            color: JarvisTheme.textPrimary,
            fontWeight: FontWeight.w600,
          );
    final metaStyle = kIsWeb
        ? JarvisTheme.bodySmall.copyWith(
            color: JarvisTheme.textSecondary,
            fontSize: 12,
          )
        : JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted);
    return FutureBuilder<Dish?>(
      future: _loadDish(dish.dishId),
      builder: (context, snap) {
        final loaded = snap.data;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: JarvisTheme.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _changeDishAt(slot, index, dishes),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loaded?.name ?? '(dish removed)',
                        style: dishNameStyle,
                      ),
                      if (loaded != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${loaded.prepMinutes} min • ${loaded.tags.take(3).join(" · ")}',
                          style: metaStyle,
                        ),
                      ],
                      if (dish.notes != null && dish.notes!.isNotEmpty) ...[
                        const SizedBox(height: JarvisTheme.xs),
                        Text(
                          dish.notes!,
                          style: JarvisTheme.bodySmall.copyWith(
                            color: JarvisTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.close,
                    color: JarvisTheme.textMuted, size: 18),
                onPressed: () => _removeDishAt(slot, index, dishes),
                visualDensity: VisualDensity.compact,
                splashRadius: 20,
              ),
            ],
          ),
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
