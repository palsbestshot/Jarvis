// MealsSection — the "Meal Plans" board tab for Rakhi. Renders a
// month-at-a-glance calendar grid. Each day cell shows the date number
// plus up to 5 tiny dots indicating which slots are planned. Tap a day
// to open MealDayDetailScreen.
//
// Also owns the one-time dish catalog seeding: the first time Rakhi
// opens this section on a fresh account, we write the 84 seed dishes
// to `users/rakhi/dish_catalog`. Idempotent — safe across restarts.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../data/indian_dish_seed.dart';
import '../../models/dish.dart';
import '../../models/meal_plan_day.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import 'meal_day_detail_screen.dart';

class MealsSection extends StatefulWidget {
  final UserProfile user;
  const MealsSection({super.key, required this.user});

  @override
  State<MealsSection> createState() => _MealsSectionState();
}

class _MealsSectionState extends State<MealsSection> {
  final _firestore = FirestoreService();
  // First day of the month we're currently looking at. Always normalised
  // to midnight on the 1st so equality checks work.
  late DateTime _visibleMonth;
  bool _seedChecked = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    // Seed on first open — fire and forget.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSeed());
  }

  Future<void> _maybeSeed() async {
    if (_seedChecked) return;
    _seedChecked = true;
    try {
      final seeds = IndianDishSeed.all().map((d) {
        final m = d.toMap();
        m['id'] = d.id; // let FirestoreService use it as the doc id
        return m;
      }).toList();
      await _firestore.seedDishCatalog(widget.user.id, seedDishes: seeds);
    } catch (_) {/* non-fatal — Rakhi can still add dishes manually */}
  }

  void _prevMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    });
  }

  String _dateKey(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = _visibleMonth;
    final lastOfMonth = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0);
    final fromKey = _dateKey(firstOfMonth);
    final toKey = _dateKey(lastOfMonth);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestore.mealPlanRangeStream(widget.user.id, fromKey, toKey),
      builder: (context, snapshot) {
        final byDateKey = <String, MealPlanDay>{};
        if (snapshot.hasData) {
          for (final raw in snapshot.data!) {
            final dateKey = (raw['date_key'] ?? raw['id'] ?? '').toString();
            if (dateKey.isEmpty) continue;
            // Build a minimal MealPlanDay from the raw map — mealPlanRangeStream
            // returns `id` via the helper; our fromDoc wants a DocumentSnapshot.
            // We can just call the same field extraction inline.
            final slots = <MealSlotId, MealSlot?>{};
            for (final s in MealSlotId.values) {
              final v = raw[s.value];
              if (v is Map<String, dynamic>) {
                try {
                  slots[s] = MealSlot.fromMap(v);
                } catch (_) {
                  slots[s] = null;
                }
              } else {
                slots[s] = null;
              }
            }
            byDateKey[dateKey] = MealPlanDay(
              dateKey: dateKey,
              slots: slots,
            );
          }
        }

        return Column(
          children: [
            _buildMonthHeader(),
            const SizedBox(height: JarvisTheme.sm),
            _buildWeekdayStrip(),
            const SizedBox(height: JarvisTheme.xs),
            Expanded(
              child: _buildCalendarGrid(firstOfMonth, lastOfMonth, byDateKey),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMonthHeader() {
    final label = DateFormat('MMMM yyyy').format(_visibleMonth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JarvisTheme.md,
        JarvisTheme.sm,
        JarvisTheme.md,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left),
            color: JarvisTheme.textSecondary,
            tooltip: 'Previous month',
          ),
          Text(label, style: JarvisTheme.headingMedium),
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right),
            color: JarvisTheme.textSecondary,
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayStrip() {
    // Week starts Monday — Rakhi's India calendar convention
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: JarvisTheme.md),
      child: Row(
        children: labels
            .map((l) => Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: JarvisTheme.bodySmall.copyWith(
                        color: JarvisTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid(
    DateTime firstOfMonth,
    DateTime lastOfMonth,
    Map<String, MealPlanDay> byDateKey,
  ) {
    // Monday = 1, Sunday = 7. We render 6 rows x 7 cols and pad with blanks
    // at the start (and end) to keep the 1st aligned under the correct weekday.
    final startWeekday = firstOfMonth.weekday; // 1..7 (Mon..Sun)
    final daysInMonth = lastOfMonth.day;
    final totalCells = 42; // 6 weeks
    final today = DateTime.now();
    final todayKey = _dateKey(today);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JarvisTheme.md,
        0,
        JarvisTheme.md,
        JarvisTheme.md,
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.78, // slightly taller than wide — room for dots
        ),
        itemCount: totalCells,
        itemBuilder: (context, index) {
          // Position 0 corresponds to the cell for startWeekday (Mon=1 → index 0).
          final dayOffset = index - (startWeekday - 1);
          if (dayOffset < 0 || dayOffset >= daysInMonth) {
            return const SizedBox.shrink();
          }
          final day = dayOffset + 1;
          final cellDate = DateTime(firstOfMonth.year, firstOfMonth.month, day);
          final cellKey = _dateKey(cellDate);
          final plan = byDateKey[cellKey];
          final isToday = cellKey == todayKey;
          return _DayCell(
            day: day,
            isToday: isToday,
            accent: widget.user.accentColor,
            plan: plan,
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MealDayDetailScreen(
                  user: widget.user,
                  date: cellDate,
                ),
              ));
            },
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final Color accent;
  final MealPlanDay? plan;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.accent,
    required this.plan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPlans = plan != null && plan!.hasAnyPlanned;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JarvisTheme.small),
      child: Container(
        decoration: BoxDecoration(
          color: JarvisTheme.surface2,
          border: Border.all(
            color: isToday ? accent : Colors.transparent,
            width: isToday ? 1.5 : 0,
          ),
          borderRadius: BorderRadius.circular(JarvisTheme.small),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$day',
              style: JarvisTheme.bodyMedium.copyWith(
                color: JarvisTheme.textPrimary,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasPlans)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: MealSlotId.values.map((s) {
                    final planned =
                        plan!.slot(s) != null && plan!.slot(s)!.dishId.isNotEmpty;
                    return Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: planned
                            ? accent
                            : JarvisTheme.textMuted.withOpacity(0.25),
                      ),
                    );
                  }).toList(),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
