// DishPickerSheet — bottom sheet that lets Rakhi pick a dish for a
// given slot. Three tabs: "For <slot>" (pre-filtered to dishes that
// list this slot in meal_types), "All", and "Custom" (her own adds).
// Also has a search bar on top that filters each tab live.
//
// `+ New dish` button at the bottom opens CustomDishForm for a
// Rakhi-added dish, which lands back here as a fresh list entry.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/dish.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';
import 'custom_dish_form.dart';

/// Returned to MealDayDetailScreen when Rakhi picks a dish.
class DishPickResult {
  final String dishId;
  final String? notes;
  const DishPickResult({required this.dishId, this.notes});
}

class DishPickerSheet extends StatefulWidget {
  final UserProfile user;
  final MealSlotId slot;
  /// When `currentDishId` is set, we show a "currently:" pill so Rakhi
  /// sees what she's replacing.
  final String? currentDishId;

  const DishPickerSheet({
    super.key,
    required this.user,
    required this.slot,
    this.currentDishId,
  });

  @override
  State<DishPickerSheet> createState() => _DishPickerSheetState();
}

class _DishPickerSheetState extends State<DishPickerSheet>
    with SingleTickerProviderStateMixin {
  final _firestore = FirestoreService();
  final _searchCtrl = TextEditingController();
  String _query = '';
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  List<Dish> _filter(List<Dish> dishes, {bool slotFilter = false}) {
    final q = _query.trim().toLowerCase();
    return dishes.where((d) {
      if (slotFilter && !d.mealTypes.contains(widget.slot)) return false;
      if (q.isEmpty) return true;
      if (d.name.toLowerCase().contains(q)) return true;
      if ((d.nameHindi ?? '').toLowerCase().contains(q)) return true;
      if (d.tags.any((t) => t.toLowerCase().contains(q))) return true;
      if (d.ingredients.any((i) => i.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Sheet fills most of the screen; rounded top corners, dark theme.
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
                padding: const EdgeInsets.symmetric(horizontal: JarvisTheme.md),
                child: Text(
                  'Pick ${widget.slot.label.toLowerCase()}',
                  style: JarvisTheme.headingMedium,
                ),
              ),
              const SizedBox(height: JarvisTheme.sm),
              _buildSearchField(),
              const SizedBox(height: JarvisTheme.sm),
              TabBar(
                controller: _tab,
                labelColor: widget.user.accentColor,
                unselectedLabelColor: JarvisTheme.textSecondary,
                indicatorColor: widget.user.accentColor,
                tabs: [
                  Tab(text: 'For ${widget.slot.label.toLowerCase()}'),
                  const Tab(text: 'All'),
                  const Tab(text: 'Custom'),
                ],
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _firestore.dishCatalogStream(widget.user.id),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final all = snap.data!.map((m) {
                      final id = m['id']?.toString() ?? '';
                      return Dish(
                        id: id,
                        name: (m['name'] ?? '').toString(),
                        nameHindi: m['name_hindi']?.toString(),
                        mealTypes: ((m['meal_types'] as List?) ?? [])
                            .map((v) => MealSlotId.fromValue(v?.toString()))
                            .whereType<MealSlotId>()
                            .toList(),
                        prepMinutes: (m['prep_minutes'] is num)
                            ? (m['prep_minutes'] as num).toInt()
                            : 20,
                        tags: ((m['tags'] as List?) ?? [])
                            .map((e) => e.toString())
                            .toList(),
                        ingredients: ((m['ingredients'] as List?) ?? [])
                            .map((e) => e.toString())
                            .toList(),
                        notes: m['notes']?.toString(),
                        timesUsed: (m['times_used'] is num)
                            ? (m['times_used'] as num).toInt()
                            : 0,
                        isCustom: m['is_custom'] == true,
                        imageUrl: m['image_url']?.toString(),
                      );
                    }).toList();
                    return TabBarView(
                      controller: _tab,
                      children: [
                        _dishList(_filter(all, slotFilter: true),
                            scrollController),
                        _dishList(_filter(all), scrollController),
                        _dishList(
                          _filter(all.where((d) => d.isCustom).toList()),
                          scrollController,
                        ),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(JarvisTheme.md),
                  child: OutlinedButton.icon(
                    onPressed: _openNewDishForm,
                    icon: const Icon(Icons.add),
                    label: const Text('New dish'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.user.accentColor,
                      side: BorderSide(color: widget.user.accentColor),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(JarvisTheme.small),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: JarvisTheme.md),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(color: JarvisTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search dishes, ingredients, tags…',
          hintStyle: TextStyle(color: JarvisTheme.textMuted),
          prefixIcon:
              Icon(Icons.search, color: JarvisTheme.textMuted),
          filled: true,
          fillColor: JarvisTheme.surface2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(JarvisTheme.small),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _dishList(List<Dish> dishes, ScrollController controller) {
    if (dishes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(JarvisTheme.lg),
          child: Text(
            _query.isEmpty
                ? 'No dishes yet.\nTap + New dish to add one.'
                : 'No matches for "$_query".',
            textAlign: TextAlign.center,
            style: JarvisTheme.bodyMedium
                .copyWith(color: JarvisTheme.textMuted),
          ),
        ),
      );
    }
    if (kIsWeb) {
      return GridView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(
            horizontal: JarvisTheme.md, vertical: JarvisTheme.xs),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: dishes.length,
        itemBuilder: (context, i) => _dishCard(dishes[i]),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: JarvisTheme.md),
      itemCount: dishes.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: JarvisTheme.surface2,
      ),
      itemBuilder: (context, i) {
        final d = dishes[i];
        final isCurrent = d.id == widget.currentDishId;
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  d.name,
                  style: JarvisTheme.bodyLarge
                      .copyWith(color: JarvisTheme.textPrimary),
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.user.accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'current',
                    style: JarvisTheme.bodySmall.copyWith(
                      color: widget.user.accentColor,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            '${d.prepMinutes} min • ${d.tags.take(3).join(" · ")}',
            style: JarvisTheme.bodySmall
                .copyWith(color: JarvisTheme.textMuted),
          ),
          trailing: TextButton(
            onPressed: () {
              Navigator.of(context).pop(DishPickResult(dishId: d.id));
            },
            child: Text('Pick',
                style: TextStyle(color: widget.user.accentColor)),
          ),
          onTap: () {
            Navigator.of(context).pop(DishPickResult(dishId: d.id));
          },
        );
      },
    );
  }

  Widget _dishCard(Dish d) {
    final isCurrent = d.id == widget.currentDishId;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () =>
          Navigator.of(context).pop(DishPickResult(dishId: d.id)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: JarvisTheme.surface2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF9D6E2).withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 70,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (d.imageUrl != null && d.imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: d.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _emojiPlaceholder(d),
                        errorWidget: (_, __, ___) => _emojiPlaceholder(d),
                      )
                    : _emojiPlaceholder(d),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 15,
                      color: JarvisTheme.rakhiAccentDeep,
                    ),
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.user.accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '•',
                      style: TextStyle(
                        color: widget.user.accentColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              d.tags.isNotEmpty
                  ? d.tags.first
                  : '${d.prepMinutes} min',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10,
                color: JarvisTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiPlaceholder(Dish d) {
    final emoji = _emojiForDish(d);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            JarvisTheme.surface2,
            JarvisTheme.surface2.withOpacity(0.6),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 28)),
    );
  }

  String _emojiForDish(Dish d) {
    final tags = d.tags.map((t) => t.toLowerCase()).toList();
    final name = d.name.toLowerCase();
    if (tags.contains('lentils') ||
        name.contains('dal') ||
        name.contains('sambar')) return '🫘';
    if (tags.contains('rice') || name.contains('rice') ||
        name.contains('biryani') || name.contains('pulao')) return '🍚';
    if (tags.contains('bread') || name.contains('roti') ||
        name.contains('paratha') || name.contains('naan')) return '🫓';
    if (tags.contains('sweet') || name.contains('ladoo') ||
        name.contains('halwa') || name.contains('kheer')) return '🍮';
    if (tags.contains('vegetable') || tags.contains('sabzi') ||
        name.contains('sabzi')) return '🥬';
    if (tags.contains('snack') || name.contains('samosa') ||
        name.contains('pakora')) return '🥟';
    if (tags.contains('drink') || name.contains('lassi') ||
        name.contains('chai') || name.contains('tea')) return '🥛';
    if (tags.contains('breakfast') || name.contains('poha') ||
        name.contains('upma') || name.contains('idli')) return '🍛';
    return '🍽️';
  }

  Future<void> _openNewDishForm() async {
    final newDishId = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) =>
            CustomDishForm(user: widget.user, defaultSlot: widget.slot),
      ),
    );
    if (newDishId != null && mounted) {
      // Pop the sheet immediately with the new dish selected —
      // the day detail will assign it to the slot.
      Navigator.of(context).pop(DishPickResult(dishId: newDishId));
    }
  }
}
