// CustomDishForm — form Rakhi uses to add her own dishes to the
// catalog. Pops back with the new dish id so the caller (dish picker
// sheet) can immediately assign it to the slot she was editing.
//
// Required: name. Everything else optional — she can add tags and
// ingredients later. Meal types default to the slot she was adding
// from, but she can toggle more.

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/dish.dart';
import '../../models/user_profile.dart';
import '../../services/firestore_service.dart';

class CustomDishForm extends StatefulWidget {
  final UserProfile user;
  final MealSlotId? defaultSlot;

  const CustomDishForm({
    super.key,
    required this.user,
    this.defaultSlot,
  });

  @override
  State<CustomDishForm> createState() => _CustomDishFormState();
}

class _CustomDishFormState extends State<CustomDishForm> {
  final _firestore = FirestoreService();
  final _nameCtrl = TextEditingController();
  final _hindiCtrl = TextEditingController();
  final _prepCtrl = TextEditingController(text: '20');
  final _tagsCtrl = TextEditingController();
  final _ingredientsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late final Set<MealSlotId> _slots;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _slots = {
      if (widget.defaultSlot != null) widget.defaultSlot!,
    };
    if (_slots.isEmpty) _slots.add(MealSlotId.lunch);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hindiCtrl.dispose();
    _prepCtrl.dispose();
    _tagsCtrl.dispose();
    _ingredientsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your dish a name first')),
      );
      return;
    }
    if (_slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one meal slot')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final prepMinutes = int.tryParse(_prepCtrl.text.trim()) ?? 20;
      final tags = _splitCsv(_tagsCtrl.text);
      final ingredients = _splitCsv(_ingredientsCtrl.text);
      final data = {
        'name': name,
        if (_hindiCtrl.text.trim().isNotEmpty)
          'name_hindi': _hindiCtrl.text.trim(),
        'meal_types': _slots.map((s) => s.value).toList(),
        'prep_minutes': prepMinutes,
        'tags': tags,
        'ingredients': ingredients,
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
      };
      final id = await _firestore.createDish(widget.user.id, data);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  List<String> _splitCsv(String raw) {
    return raw
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisTheme.background,
      appBar: AppBar(
        backgroundColor: JarvisTheme.background,
        elevation: 0,
        title: const Text('New dish', style: JarvisTheme.headingMedium),
        iconTheme: const IconThemeData(color: JarvisTheme.textPrimary),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? 'Saving…' : 'Save',
              style: TextStyle(color: widget.user.accentColor),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(JarvisTheme.md),
        children: [
          _field(_nameCtrl, 'Name', hint: 'e.g. Matar Paneer'),
          _field(_hindiCtrl, 'Hindi name (optional)',
              hint: 'e.g. मटर पनीर'),
          const SizedBox(height: JarvisTheme.md),
          const Text('Meal slots', style: JarvisTheme.bodySmall),
          const SizedBox(height: JarvisTheme.xs),
          Wrap(
            spacing: JarvisTheme.xs,
            runSpacing: JarvisTheme.xs,
            children: MealSlotId.values.map((s) {
              final selected = _slots.contains(s);
              return FilterChip(
                label: Text(s.label),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _slots.add(s);
                    } else {
                      _slots.remove(s);
                    }
                  });
                },
                selectedColor: widget.user.accentColor.withOpacity(0.3),
                backgroundColor: JarvisTheme.surface2,
                labelStyle: TextStyle(
                  color: selected
                      ? widget.user.accentColor
                      : JarvisTheme.textSecondary,
                ),
                side: BorderSide.none,
              );
            }).toList(),
          ),
          const SizedBox(height: JarvisTheme.md),
          _field(_prepCtrl, 'Prep minutes',
              keyboardType: TextInputType.number),
          const SizedBox(height: JarvisTheme.md),
          _field(_tagsCtrl, 'Tags (comma-separated)',
              hint: 'veg, quick, protein'),
          const SizedBox(height: JarvisTheme.md),
          _field(_ingredientsCtrl, 'Ingredients (one per line or comma-sep)',
              hint: 'paneer, tomato, peas, cream',
              maxLines: 3),
          const SizedBox(height: JarvisTheme.md),
          _field(_notesCtrl, 'Notes (optional)',
              hint: 'tips, serving suggestions…', maxLines: 2),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: JarvisTheme.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textMuted)),
          const SizedBox(height: JarvisTheme.xs),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: const TextStyle(color: JarvisTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: JarvisTheme.textMuted),
              filled: true,
              fillColor: JarvisTheme.surface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(JarvisTheme.small),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
