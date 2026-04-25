import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class EditHabitBottomSheet extends ConsumerStatefulWidget {
  final String habitId;
  final Map<String, dynamic> habitData;
  final VoidCallback onHabitUpdated;

  const EditHabitBottomSheet({
    super.key,
    required this.habitId,
    required this.habitData,
    required this.onHabitUpdated,
  });

  @override
  ConsumerState<EditHabitBottomSheet> createState() => _EditHabitBottomSheetState();
}

class _EditHabitBottomSheetState extends ConsumerState<EditHabitBottomSheet> {
  final FirestoreService _firestoreService = FirestoreService();
  late TextEditingController _titleController;
  TimeOfDay? _selectedTime;
  late String _selectedFrequency;
  late bool _isActive;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.habitData['title'] ?? '');
    _selectedTime = _parseTimeOfDay(widget.habitData['time_of_day']?.toString());
    _selectedFrequency = widget.habitData['frequency'] ?? AppConstants.recurringFrequencies.first;
    _isActive = widget.habitData['active'] ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final user = ref.read(activeUserProvider);
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _firestoreService.updateRecurringTask(user.id, widget.habitId, {
        'title': title,
        'frequency': _selectedFrequency,
        'time_of_day': _formatTimeOfDay(_selectedTime),
        'active': _isActive,
      });
      widget.onHabitUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating habit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: bottomInset + 20,
      ),
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Edit Habit',
                style: JarvisTheme.bodyLarge.copyWith(
                  color: JarvisTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: JarvisTheme.textMuted, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Habit name',
              hintStyle: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
              filled: true,
              fillColor: JarvisTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Text(
            'Frequency',
            style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppConstants.recurringFrequencies.map((freq) {
              final isSelected = _selectedFrequency == freq;
              return GestureDetector(
                onTap: () => setState(() => _selectedFrequency = freq),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? JarvisTheme.pallavAccent.withOpacity(0.2) : JarvisTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? JarvisTheme.pallavAccent : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    freq,
                    style: JarvisTheme.bodySmall.copyWith(
                      color: isSelected ? JarvisTheme.pallavAccent : JarvisTheme.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: JarvisTheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: JarvisTheme.textMuted, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedTime == null
                          ? 'Pick reminder time (optional)'
                          : _selectedTime!.format(context),
                      style: JarvisTheme.bodyMedium.copyWith(
                        color: _selectedTime == null
                            ? JarvisTheme.textMuted
                            : JarvisTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (_selectedTime != null)
                    GestureDetector(
                      onTap: () => setState(() => _selectedTime = null),
                      child: Icon(
                        Icons.close,
                        color: JarvisTheme.textMuted,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active',
                style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
              ),
              Switch(
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
                activeColor: JarvisTheme.pallavAccent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: JarvisTheme.pallavAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      'Save Changes',
                      style: JarvisTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// Stored as 24h "HH:mm" so the value is unambiguous regardless of locale.
// Legacy free-text values like "7:00 AM" are still parsed for display.

String? _formatTimeOfDay(TimeOfDay? t) {
  if (t == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

TimeOfDay? _parseTimeOfDay(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*$').firstMatch(s);
  if (m != null) {
    final h = int.tryParse(m.group(1)!);
    final mm = int.tryParse(m.group(2)!);
    if (h != null && mm != null && h >= 0 && h < 24 && mm >= 0 && mm < 60) {
      return TimeOfDay(hour: h, minute: mm);
    }
  }
  final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*$').firstMatch(s);
  if (ampm != null) {
    var h = int.tryParse(ampm.group(1)!) ?? 0;
    final mm = int.tryParse(ampm.group(2)!) ?? 0;
    final isPm = ampm.group(3)!.toUpperCase() == 'PM';
    if (h == 12) h = 0;
    if (isPm) h += 12;
    if (h >= 0 && h < 24 && mm >= 0 && mm < 60) {
      return TimeOfDay(hour: h, minute: mm);
    }
  }
  return null;
}
