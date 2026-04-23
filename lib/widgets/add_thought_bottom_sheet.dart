import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class AddThoughtBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback onThoughtAdded;

  const AddThoughtBottomSheet({super.key, required this.onThoughtAdded});

  @override
  ConsumerState<AddThoughtBottomSheet> createState() => _AddThoughtBottomSheetState();
}

class _AddThoughtBottomSheetState extends ConsumerState<AddThoughtBottomSheet> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  String _selectedCategory = AppConstants.thoughtCategories.last; // 'General'
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) return;

    final user = ref.read(activeUserProvider);
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _firestoreService.saveThought(user.id, {
        'title': title,
        'content': content,
        'category': _selectedCategory,
      });
      widget.onThoughtAdded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving thought: $e')),
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
                'New Thought',
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
              hintText: 'Title',
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
          const SizedBox(height: 10),
          TextField(
            controller: _contentController,
            style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Write your thought...',
              hintStyle: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
              filled: true,
              fillColor: JarvisTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Category',
            style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: AppConstants.thoughtCategories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
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
                    cat,
                    style: JarvisTheme.bodySmall.copyWith(
                      color: isSelected ? JarvisTheme.pallavAccent : JarvisTheme.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
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
                      'Save Thought',
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
