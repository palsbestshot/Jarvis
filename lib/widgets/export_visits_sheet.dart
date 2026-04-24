// "Share visits CSV" bottom sheet.
//
// Opens from the Board > Time section's export icon. Lets Pallav pick a
// date range and (optionally) a contact-type filter, then fires
// VisitExportService.exportAndShare which writes a CSV to the temp dir
// and opens the platform share sheet (Gmail, Drive, Keep, etc.).
//
// Default range is last-30-days because that's the sweet spot for "this
// month's visits" — but the range is editable so weekly or quarterly
// pulls work too.

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/time_categories.dart';
import '../models/user_profile.dart';
import '../services/visit_export_service.dart';

Future<void> showExportVisitsSheet({
  required BuildContext context,
  required UserProfile user,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: JarvisTheme.surface2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ExportVisitsSheet(user: user),
  );
}

class _ExportVisitsSheet extends StatefulWidget {
  final UserProfile user;
  const _ExportVisitsSheet({required this.user});

  @override
  State<_ExportVisitsSheet> createState() => _ExportVisitsSheetState();
}

class _ExportVisitsSheetState extends State<_ExportVisitsSheet> {
  late DateTime _from;
  late DateTime _to;
  String? _contactType; // null = All
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 30));
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.dark(
              primary: widget.user.accentColor,
              onPrimary: Colors.black,
              surface: JarvisTheme.surface,
              onSurface: JarvisTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final result = await VisitExportService().exportAndShare(
        userId: widget.user.id,
        from: _from,
        to: _to,
        contactType: _contactType,
      );
      if (!mounted) return;
      if (result.count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No visits in this range.')),
        );
        setState(() => _sharing = false);
        return;
      }
      // Share sheet is up; close the bottom sheet so the user returns to
      // the board after picking an app.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
      setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.user.accentColor;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: JarvisTheme.textMuted.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.ios_share, size: 20, color: accent),
                const SizedBox(width: 8),
                Text(
                  'Share visits CSV',
                  style: JarvisTheme.bodyLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Exports all visit fields to a CSV and opens the share sheet.',
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _dateField(label: 'From', value: _from, isFrom: true)),
                const SizedBox(width: 10),
                Expanded(child: _dateField(label: 'To', value: _to, isFrom: false)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Contact type',
              style: JarvisTheme.labelMedium
                  .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _filterChip(
                  label: 'All',
                  selected: _contactType == null,
                  onTap: () => setState(() => _contactType = null),
                  accent: accent,
                ),
                ...VisitContactTypes.all.map((t) => _filterChip(
                      label: t.label,
                      selected: _contactType == t.id,
                      onTap: () => setState(() => _contactType = t.id),
                      accent: accent,
                    )),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: Text(_sharing ? 'Preparing...' : 'Share CSV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime value,
    required bool isFrom,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${value.year}-${two(value.month)}-${two(value.day)}';
    return InkWell(
      onTap: () => _pickDate(isFrom: isFrom),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: JarvisTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JarvisTheme.surface2, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: JarvisTheme.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.2) : JarvisTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : JarvisTheme.surface2,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: JarvisTheme.bodySmall.copyWith(
            color: selected ? accent : JarvisTheme.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
