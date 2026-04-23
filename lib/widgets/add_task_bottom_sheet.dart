import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';

class AddTaskBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback onTaskAdded;

  const AddTaskBottomSheet({
    super.key,
    required this.onTaskAdded,
  });

  @override
  ConsumerState<AddTaskBottomSheet> createState() => _AddTaskBottomSheetState();
}

class _AddTaskBottomSheetState extends ConsumerState<AddTaskBottomSheet> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  String? _selectedCategory;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _selectedPriority = 'medium';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final initialDate = _selectedDate ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _selectTime() async {
    final initialTime = _selectedTime ?? TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    
    if (pickedTime != null) {
      setState(() {
        _selectedTime = pickedTime;
      });
    }
  }

  Future<void> _saveTask() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task title')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = ref.read(activeUserProvider);
      if (user == null) return;

      // Prepare task data
      final taskData = <String, dynamic>{
        'title': _titleController.text.trim(),
        'status': 'pending',
        'priority': _selectedPriority,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Add category if selected
      if (_selectedCategory != null) {
        taskData['category'] = _selectedCategory;
      }

      // Add due date if selected
      if (_selectedDate != null) {
        final dueDateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
        taskData['due_date'] = dueDateStr;
      }

      // Add due time if selected
      if (_selectedTime != null && _selectedDate != null) {
        final dueDateTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
        taskData['due_time'] = dueDateTime.toIso8601String();
      }

      // Save to Firestore
      await _firestoreService.createTask(user.id, taskData);

      // Dismiss keyboard
      FocusScope.of(context).unfocus();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task added successfully')),
      );

      // Close sheet and notify parent
      widget.onTaskAdded();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add task: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Widget _buildTitleField(UserProfile user) {
    return TextField(
      controller: _titleController,
      style: JarvisTheme.bodyLarge.copyWith(
        color: JarvisTheme.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'What needs to be done?',
        hintStyle: JarvisTheme.bodyLarge.copyWith(
          color: JarvisTheme.textMuted,
        ),
        border: InputBorder.none,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: user.accentColor),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: JarvisTheme.textMuted.withOpacity(0.3)),
        ),
      ),
      maxLines: 1,
    );
  }

  Widget _buildCategoryDropdown(UserProfile user) {
    // Only show category dropdown for Pallav
    if (user.id != AppConstants.pallavUserId) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Category',
          style: JarvisTheme.bodyMedium.copyWith(
            color: JarvisTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: JarvisTheme.textMuted.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: JarvisTheme.textMuted.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: user.accentColor),
            ),
            filled: true,
            fillColor: JarvisTheme.surface,
          ),
          items: AppConstants.taskCategories.map((category) {
            return DropdownMenuItem<String>(
              value: category,
              child: Text(
                category,
                style: JarvisTheme.bodyMedium.copyWith(
                  color: JarvisTheme.textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategory = value;
            });
          },
          hint: Text(
            'Select category',
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(UserProfile user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Due Date',
          style: JarvisTheme.bodyMedium.copyWith(
            color: JarvisTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _selectDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: JarvisTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: JarvisTheme.textMuted.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedDate != null
                      ? AppUtils.formatDateFromDateTime(_selectedDate!)
                      : 'No due date',
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: _selectedDate != null
                        ? JarvisTheme.textPrimary
                        : JarvisTheme.textMuted,
                  ),
                ),
                Icon(
                  Icons.calendar_today,
                  color: user.accentColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker(UserProfile user) {
    if (_selectedDate == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Due Time',
          style: JarvisTheme.bodyMedium.copyWith(
            color: JarvisTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _selectTime,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: JarvisTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: JarvisTheme.textMuted.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedTime != null
                      ? AppUtils.formatDateTime(DateTime(
                          _selectedDate!.year,
                          _selectedDate!.month,
                          _selectedDate!.day,
                          _selectedTime!.hour,
                          _selectedTime!.minute,
                        ))
                      : 'No specific time',
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: _selectedTime != null
                        ? JarvisTheme.textPrimary
                        : JarvisTheme.textMuted,
                  ),
                ),
                Icon(
                  Icons.access_time,
                  color: user.accentColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrioritySelector(UserProfile user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Priority',
          style: JarvisTheme.bodyMedium.copyWith(
            color: JarvisTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildPriorityPill('Low', user),
            const SizedBox(width: 8),
            _buildPriorityPill('Medium', user),
            const SizedBox(width: 8),
            _buildPriorityPill('High', user),
          ],
        ),
      ],
    );
  }

  Widget _buildPriorityPill(String priority, UserProfile user) {
    final isSelected = _selectedPriority == priority.toLowerCase();
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPriority = priority.toLowerCase();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? user.accentColor : JarvisTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? user.accentColor : JarvisTheme.textMuted.withOpacity(0.3),
            ),
          ),
          child: Center(
            child: Text(
              priority,
              style: JarvisTheme.bodyMedium.copyWith(
                color: isSelected ? Colors.white : JarvisTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton(UserProfile user) {
    return Align(
      alignment: Alignment.bottomRight,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _saveTask,
        style: ElevatedButton.styleFrom(
          backgroundColor: user.accentColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Add Task'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(activeUserProvider);
    if (user == null) return const SizedBox();

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: JarvisTheme.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add New Task',
              style: JarvisTheme.headingMedium.copyWith(
                color: JarvisTheme.textPrimary,
              ),
            ),
            
            const SizedBox(height: 24),
            
            _buildTitleField(user),
            
            _buildCategoryDropdown(user),
            
            _buildDatePicker(user),
            
            _buildTimePicker(user),
            
            _buildPrioritySelector(user),
            
            const SizedBox(height: 32),
            
            _buildSaveButton(user),
          ],
        ),
      ),
    );
  }
}