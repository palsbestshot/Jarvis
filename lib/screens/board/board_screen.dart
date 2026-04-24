import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../models/user_profile.dart';
import '../../models/task.dart';
import '../../models/thought.dart';
import '../../models/goal.dart';
import '../../models/finance.dart';
import '../../providers/finance_provider.dart';
import '../../models/meal.dart';
import '../../widgets/add_task_bottom_sheet.dart';
import '../../widgets/edit_task_bottom_sheet.dart';
import '../../widgets/edit_habit_bottom_sheet.dart';
import '../../widgets/add_thought_bottom_sheet.dart';
import '../../widgets/motivation_ring.dart';
import '../goals/roadmap_detail_screen.dart';
import '../meals/meals_section.dart';
import '../../core/people_directory.dart';
import '../../widgets/call_followup_sheet.dart';
import '../../services/home_widget_service.dart';
import 'time_section.dart';

class BoardScreen extends ConsumerStatefulWidget {
  final ValueNotifier<int>? sectionNotifier;
  final VoidCallback? onSwitchToChat;

  const BoardScreen({super.key, this.sectionNotifier, this.onSwitchToChat});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> with AutomaticKeepAliveClientMixin {
  final FirestoreService _firestoreService = FirestoreService();
  int _selectedSectionIndex = 0;
  // Sections are derived from the active user at render time instead of
  // cached in initState. The old initState-only path had a race on the
  // Flutter Web PWA: splash_screen's kIsWeb auto-login sets Rakhi async,
  // and BoardScreen's initState sometimes fired with a null user, so
  // _userSections stayed empty and the whole board rendered blank until
  // manual reload. Reading from ref.watch(activeUserProvider) on every
  // build keeps us in sync with auth state.
  List<String> _userSections = [];
  bool _isSectionMenuOpen = false;
  bool _isSelectionMode = false;
  Set<String> _selectedTaskIds = {};
  bool _showCompleted = false;
  String? _expandedThoughtId;
  String _goalFilter = 'active'; // 'all' | 'active' | 'done'
  bool _isSeedingRoadmap = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUserSections();
    widget.sectionNotifier?.addListener(_onSectionNotifierChanged);
  }

  void _onSectionNotifierChanged() {
    if (mounted && widget.sectionNotifier != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _selectedSectionIndex = widget.sectionNotifier!.value;
        _isSectionMenuOpen = false;
      });
    }
  }

  @override
  void dispose() {
    widget.sectionNotifier?.removeListener(_onSectionNotifierChanged);
    super.dispose();
  }

  /// Pulls the section list from the active user and syncs local state.
  /// Called from initState (for the first render on Android where auth
  /// loads synchronously) and again from build() on web if the race
  /// described above left _userSections empty.
  void _loadUserSections() {
    final user = ref.read(activeUserProvider);
    if (user != null) {
      setState(() {
        _userSections = user.boardSections;
      });
    }
  }

  /// Cheap string-list equality for the race-repair check in build().
  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _buildGreetingSection(UserProfile user) {
    final greeting = AppUtils.getGreeting();
    final todayDate = AppUtils.getTodayDateFormatted();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, ${user.name}',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 24,
                      color: JarvisTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    todayDate,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            _buildSectionDropdown(user),
          ],
        ),
        const SizedBox(height: 16),
        _buildActivityProgress(user),
      ],
    );
  }

  Widget _buildActivityProgress(UserProfile user) {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('tasks')
          .where('due_date', isEqualTo: todayStr)
          .snapshots(),
      builder: (context, snapshot) {
        int total = 0;
        int done = 0;

        if (snapshot.hasData) {
          total = snapshot.data!.docs.length;
          done = snapshot.data!.docs
              .where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'done')
              .length;
        }

        String motivationText;
        if (!snapshot.hasData) {
          motivationText = 'Loading...';
        } else if (total == 0) {
          motivationText = 'No tasks today.';
        } else if (done == total) {
          motivationText = 'All done!';
        } else {
          motivationText = '${total - done} remaining';
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MotivationRing(
              completed: done,
              total: total,
              size: 80,
              ringColor: user.accentColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s Tasks',
                    style: JarvisTheme.labelMedium.copyWith(
                      color: JarvisTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total == 0 ? 'Nothing due today' : '$done of $total done',
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    motivationText,
                    style: JarvisTheme.bodySmall.copyWith(
                      color: JarvisTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionDropdown(UserProfile user) {
    if (_userSections.isEmpty) return const SizedBox();

    final currentSection = _userSections[_selectedSectionIndex];

    return PopupMenuButton<int>(
      onSelected: (index) {
        FocusScope.of(context).unfocus();
        setState(() => _selectedSectionIndex = index);
        widget.sectionNotifier?.value = index;
      },
      offset: const Offset(0, 40),
      color: JarvisTheme.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => _userSections.asMap().entries.map((entry) {
        final index = entry.key;
        final section = entry.value;
        final isSelected = index == _selectedSectionIndex;
        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              _getSectionIconSmall(section, user),
              const SizedBox(width: 10),
              Text(
                section,
                style: JarvisTheme.bodyMedium.copyWith(
                  color: isSelected ? user.accentColor : JarvisTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(Icons.circle, size: 6, color: user.accentColor),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: JarvisTheme.surface2,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: user.accentColor.withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentSection,
              style: JarvisTheme.labelMedium.copyWith(
                color: user.accentColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              color: user.accentColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Icon _getSectionIconSmall(String section, UserProfile user) {
    switch (section) {
      case 'Tasks':
        return const Icon(Icons.checklist, color: Colors.blue, size: 18);
      case 'Time':
        return const Icon(Icons.timer_outlined, color: Colors.cyan, size: 18);
      case 'Habits':
        return const Icon(Icons.repeat, color: Colors.green, size: 18);
      case 'Thoughts':
        return const Icon(Icons.lightbulb_outline, color: Colors.orange, size: 18);
      case 'Finance':
        return const Icon(Icons.account_balance_wallet_outlined, color: Colors.purple, size: 18);
      case 'Goals':
        return const Icon(Icons.flag_outlined, color: Colors.red, size: 18);
      case 'Meals':
      case 'Meal Plans':
        return const Icon(Icons.restaurant_outlined, color: Colors.teal, size: 18);
      default:
        return const Icon(Icons.dashboard_outlined, color: Colors.grey, size: 18);
    }
  }

  Widget _buildSectionContent(UserProfile user) {
    if (_userSections.isEmpty) return const SizedBox();
    
    final section = _userSections[_selectedSectionIndex];
    
    switch (section) {
      case 'Tasks':
        return _buildTasksSection(user);
      case 'Time':
        return user.id == AppConstants.pallavUserId
            ? TimeSection(user: user)
            : _buildEmptyState('Time tracking is only enabled for Pallav.');
      case 'Habits':
        return _buildHabitsSection(user);
      case 'Thoughts':
        return _buildThoughtsSection(user);
      case 'Finance':
        // Finance section now available to both Pallav and Rakhi
        // (each user has their own `users/{uid}/finance` subtree).
        return _buildFinanceSection(user);
      case 'Goals':
        return _buildGoalsSection(user);
      case 'Meals':
      case 'Meal Plans':
        // Meal-planner is Rakhi-only (Pallav's apk doesn't ship the UI).
        return user.id == AppConstants.rakhiUserId
            ? MealsSection(user: user)
            : _buildEmptyState('Meal plans are for Rakhi');
      default:
        return _buildEmptyState('Section coming soon');
    }
  }

  Widget _buildTasksSection(UserProfile user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('tasks')
          .orderBy('due_date', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Push today's task counts to the Android home widget so the
        // pinned widget stays in sync whenever tasks change in the app.
        // Fire-and-forget — no await, doesn't block the UI. Also deferred
        // to a post-frame callback so nothing plugin-related runs during
        // this StreamBuilder's build (was suspected as a crash path when
        // the widget is enabled on some OEM launchers).
        final snapData = snapshot.data!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          HomeWidgetService.pushFromSnapshot(snapData);
        });

        final allTasks = snapshot.data!.docs;
        final tasks = _showCompleted
            ? allTasks
            : allTasks.where((t) => (t.data() as Map<String, dynamic>)['status'] != 'done').toList();

        final doneCount = allTasks.where((t) => (t.data() as Map<String, dynamic>)['status'] == 'done').length;

        if (tasks.isEmpty && doneCount == 0) {
          return _buildEmptyState('No tasks yet. Tell JARVIS what you need to do.');
        }

        // Group by date label, then sort each group.
        //
        // Daily rhythm Pallav actually works in:
        //   1. Fire off all delegations first — they're cheap for him and
        //      every minute they sit is a minute the team is blocked.
        //   2. Then chew through his own tasks high → medium → low.
        //
        // Composite sort: action_type rank (delegate=0, self=1) then
        // priority rank (high=0, medium=1, low=2). Non-email tasks have
        // no action_type so they default to 'self' and slot alongside
        // his own priority-sorted work.
        const delegateRank = {'delegate': 0, 'self': 1};
        const priorityRank = {'high': 0, 'medium': 1, 'low': 2};
        final grouped = <String, List<QueryDocumentSnapshot>>{};
        for (final task in tasks) {
          final data = task.data() as Map<String, dynamic>;
          final dueDate = data['due_date']?.toString();
          final label = AppUtils.getRelativeDateLabel(dueDate);
          final key = label.isEmpty ? 'No date' : label;
          grouped.putIfAbsent(key, () => []).add(task);
        }
        for (final list in grouped.values) {
          list.sort((a, b) {
            final ad = a.data() as Map<String, dynamic>;
            final bd = b.data() as Map<String, dynamic>;
            final aAction = (ad['action_type'] ?? 'self').toString();
            final bAction = (bd['action_type'] ?? 'self').toString();
            final ar = delegateRank[aAction] ?? 1;
            final br = delegateRank[bAction] ?? 1;
            if (ar != br) return ar.compareTo(br);
            final ap = priorityRank[(ad['priority'] ?? 'medium').toString()] ?? 1;
            final bp = priorityRank[(bd['priority'] ?? 'medium').toString()] ?? 1;
            return ap.compareTo(bp);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toggle row
            if (doneCount > 0)
              GestureDetector(
                onTap: () => setState(() => _showCompleted = !_showCompleted),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        _showCompleted ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 14,
                        color: JarvisTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showCompleted ? 'Hide done ($doneCount)' : 'Show done ($doneCount)',
                        style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ),

            ...grouped.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date section header
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      entry.key,
                      style: JarvisTheme.labelMedium.copyWith(
                        color: entry.key == 'Today'
                            ? user.accentColor
                            : JarvisTheme.textMuted,
                      ),
                    ),
                  ),
                  ...entry.value.map((task) {
                    final data = task.data() as Map<String, dynamic>;
                    return _buildTaskCard(user, task.id, data);
                  }),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildTaskCard(UserProfile user, String taskId, Map<String, dynamic> data) {
    final isDone = data['status'] == 'done';
    final priority = data['priority'] ?? 'medium';
    final dueDate = data['due_date']?.toString();
    final category = data['category']?.toString();
    final isSelected = _selectedTaskIds.contains(taskId);
    // Set by the `rolloverYesterdayTasks` scheduled function the first time a
    // pending task slips past its due date. Drives the amber "from <date>" chip.
    final originalDueDate = data['original_due_date']?.toString();

    // Email-intelligence task detection
    final isEmailTask = data['source'] == 'email_intelligence';
    final actionType = data['action_type']?.toString() ?? 'self';
    final delegateTo = data['delegate_to']?.toString() ?? '';
    final rawTitle = data['title']?.toString() ?? 'Untitled Task';
    final displayTitle = isEmailTask
        ? _stripEmailTitlePrefix(rawTitle)
        : rawTitle;

    Widget taskCard = GestureDetector(
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedTaskIds.add(taskId);
          });
        }
      },
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedTaskIds.remove(taskId);
              if (_selectedTaskIds.isEmpty) {
                _isSelectionMode = false;
              }
            } else {
              _selectedTaskIds.add(taskId);
            }
          });
        } else {
          // Email tasks open a detail sheet; others open edit sheet.
          if (isEmailTask) {
            _showEmailTaskSheet(user, taskId, data);
          } else {
            _showEditTaskSheet(user, taskId, data);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _isSelectionMode && isSelected
              ? user.accentColor.withOpacity(0.1)
              : JarvisTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: _isSelectionMode && isSelected
              ? Border.all(color: user.accentColor, width: 2)
              : null,
        ),
        child: Row(
          children: [
            // Selection checkbox
            if (_isSelectionMode)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? user.accentColor : Colors.transparent,
                  border: Border.all(
                    color: user.accentColor,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: JarvisTheme.textPrimary,
                      )
                    : null,
              ),

            if (_isSelectionMode)
              const SizedBox(width: 12),

            // Task details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge row: priority always, + action/tap hint for email tasks.
                  // Priority is now a readable HIGH/MED/LOW chip instead of a
                  // nearly-invisible 8×8 dot.
                  Row(
                    children: [
                      _buildPriorityBadge(priority),
                      if (isEmailTask) ...[
                        const SizedBox(width: 6),
                        _buildActionBadge(actionType, delegateTo),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.touch_app,
                          size: 12,
                          color: JarvisTheme.textMuted,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    displayTitle,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: isDone ? JarvisTheme.textMuted : JarvisTheme.textPrimary,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      fontWeight: isEmailTask ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (dueDate != null || category != null || originalDueDate != null)
                    const SizedBox(height: 4),

                  Row(
                    children: [
                      if (dueDate != null)
                        Text(
                          AppUtils.formatDate(dueDate),
                          style: JarvisTheme.bodySmall.copyWith(
                            color: JarvisTheme.textMuted,
                          ),
                        ),

                      // Rollover chip: shows if the task was originally due on
                      // an earlier date and got auto-pushed forward. Amber so
                      // it reads as "needs attention" without screaming red.
                      if (originalDueDate != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.amber.shade700.withOpacity(0.55),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 10,
                                color: Colors.amber.shade700,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'from ${AppUtils.formatDate(originalDueDate)}',
                                style: JarvisTheme.bodySmall.copyWith(
                                  color: Colors.amber.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (dueDate != null && category != null)
                        const SizedBox(width: 8),

                      if (category != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: user.accentColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            category,
                            style: JarvisTheme.bodySmall.copyWith(
                              color: user.accentColor,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Action buttons (only when not in selection mode and not done)
            if (!_isSelectionMode && !isDone) ...[
              // Done button
              GestureDetector(
                onTap: () => _firestoreService.markTaskDone(user.id, taskId),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 18, color: Colors.green),
                ),
              ),
              const SizedBox(width: 8),
              // Postpone button
              GestureDetector(
                onTap: () => _firestoreService.postponeTask(user.id, taskId),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.schedule, size: 18, color: Colors.orange),
                ),
              ),
            ],

            // Done indicator
            if (!_isSelectionMode && isDone)
              Icon(Icons.check_circle, size: 20, color: user.accentColor),
          ],
        ),
      ),
    );
    
    // Wrap with Dismissible for swipe gestures (only when not in selection mode)
    if (!_isSelectionMode) {
      return Dismissible(
        key: Key(taskId),
        direction: DismissDirection.horizontal,
        background: Container(
          color: Colors.blue.withOpacity(0.7),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          child: const Icon(Icons.edit, color: Colors.white),
        ),
        secondaryBackground: Container(
          color: Colors.red.withOpacity(0.7),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Edit action - open edit sheet and cancel dismiss
            _showEditTaskSheet(user, taskId, data);
            return false; // Don't dismiss
          } else {
            // Delete action - show confirmation dialog
            final result = await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: JarvisTheme.surface2,
                  title: Text(
                    'Delete Task',
                    style: JarvisTheme.bodyLarge.copyWith(color: JarvisTheme.textPrimary),
                  ),
                  content: Text(
                    'Delete this task?',
                    style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancel',
                        style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        'Delete',
                        style: JarvisTheme.bodyMedium.copyWith(color: Colors.red),
                      ),
                    ),
                  ],
                );
              },
            );
            
            if (result == true) {
              try {
                await _firestoreService.deleteTask(user.id, taskId);
                return true; // Dismiss the card
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete task: $e')),
                );
                return false; // Don't dismiss
              }
            }
            return false; // Don't dismiss
          }
        },
        onDismissed: (direction) {
          // This will only be called if confirmDismiss returns true
          // For delete action, the task is already deleted in confirmDismiss
          // For edit action, confirmDismiss returns false so this won't be called
        },
        child: taskCard,
      );
    }
    
    return taskCard;
  }

  void _showEditTaskSheet(UserProfile user, String taskId, Map<String, dynamic> taskData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditTaskBottomSheet(
        taskId: taskId,
        taskData: taskData,
        onTaskUpdated: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  // Strip "Do it yourself: " (new) / "Do it myself: " (legacy) / "Delegate to <Name>: "
  // prefix for compact display. Old tasks created before the second-person
  // rewrite still use the legacy prefix, so we strip both.
  String _stripEmailTitlePrefix(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(
      RegExp(r'^do it (yourself|myself)\s*[:\-]\s*', caseSensitive: false),
      '',
    );
    t = t.replaceFirst(
      RegExp(r'^delegate to\s+[^:]+:\s*', caseSensitive: false),
      '',
    );
    return t.isEmpty ? raw : t;
  }

  // Visible priority chip — replaces the old 8×8 dot that was nearly
  // impossible to read at a glance. Same visual language as the action
  // and importance badges so the badge row reads as one unit.
  Widget _buildPriorityBadge(String priority) {
    final p = priority.toLowerCase();
    Color color;
    String label;
    switch (p) {
      case 'high':
        color = Colors.red.shade600;
        label = 'HIGH';
        break;
      case 'low':
        color = Colors.blueGrey.shade400;
        label = 'LOW';
        break;
      case 'medium':
      default:
        color = Colors.orange.shade700;
        label = 'MED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildActionBadge(String actionType, String delegateTo) {
    final isDelegate = actionType == 'delegate';
    final Color color = isDelegate ? Colors.blueAccent : Colors.deepPurpleAccent;
    final String text = isDelegate && delegateTo.isNotEmpty
        ? 'DEL · ${_firstWord(delegateTo)}'
        : 'DIY';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.7), width: 1),
      ),
      child: Text(
        text,
        style: JarvisTheme.bodySmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildImportanceBadge(String importance) {
    if (importance.isEmpty) return const SizedBox.shrink();
    final Color color = importance == 'critical'
        ? Colors.redAccent
        : importance == 'actionable'
            ? Colors.orangeAccent
            : JarvisTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        importance.toUpperCase(),
        style: JarvisTheme.bodySmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _firstWord(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? s : parts.first;
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // Match an email-from string or delegate name to a KnownPerson so the
  // detail row can show a call icon when we have a mapped phone.
  // Accepts either a bare name ("Harshit Laad") or an email-style string
  // ("Harshit Laad <harshitl@...>" / "harshitl@bluestarindia.com").
  String? _matchKnownPerson(String raw) {
    if (raw.isEmpty) return null;
    // Try direct name lookup first.
    final direct = PeopleDirectory.findByName(raw);
    if (direct != null) return direct.name;
    // "Name <email>" pattern — extract the name side.
    final m = RegExp(r'^([^<]+)<').firstMatch(raw);
    if (m != null) {
      final name = m.group(1)!.trim();
      final match = PeopleDirectory.findByName(name);
      if (match != null) return match.name;
    }
    // Email-only — match by local part to the people_directory emails from
    // user_context. The simplest heuristic: scan all people and check if
    // the email substring appears in their name-derived slug. Since we
    // don't store emails here we skip this branch; delegate_email is the
    // fallback. Caller supplies name separately for delegate.
    return null;
  }

  // Same as _detailRow but if personName is mapped in contact_map,
  // adds a green call icon that dials via tel: on tap.
  Widget _buildContactAwareRow({
    required UserProfile user,
    required String label,
    required String value,
    required String? personName,
    String? taskId,
  }) {
    if (personName == null || personName.isEmpty) {
      return _detailRow(label, value);
    }
    final key = PeopleDirectory.keyOf(personName);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('contact_map')
          .doc(key)
          .snapshots(),
      builder: (ctx, snap) {
        final phone = (snap.data?.data()?['phone'] ?? '').toString().trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  label,
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textMuted),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: JarvisTheme.bodyMedium
                      .copyWith(color: JarvisTheme.textPrimary),
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => showCallFollowupSheet(
                    context: context,
                    user: user,
                    personName: personName,
                    phone: phone,
                    taskId: taskId,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.call,
                      size: 18,
                      color: user.accentColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        text.toUpperCase(),
        style: JarvisTheme.bodySmall.copyWith(
          color: JarvisTheme.textMuted,
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showEmailTaskSheet(
    UserProfile user,
    String taskId,
    Map<String, dynamic> data,
  ) {
    final actionType = data['action_type']?.toString() ?? 'self';
    final delegateTo = data['delegate_to']?.toString() ?? '';
    final delegateEmail = data['delegate_email']?.toString() ?? '';
    final emailFrom = data['email_from']?.toString() ?? '';
    final emailSubject = data['email_subject']?.toString() ?? '';
    final emailSummary = data['email_summary']?.toString() ?? '';
    final howToClose = data['how_to_close']?.toString() ?? '';
    // Self tasks use suggested_reply (first-person reply to sender).
    // Delegate tasks use forward_note (first-person Pallav → subordinate).
    // Both render in the "draft preview" block — only one is set per task.
    final actionTypeForDraft =
        (data['action_type'] ?? 'self').toString();
    final draftBodyText = actionTypeForDraft == 'delegate'
        ? (data['forward_note']?.toString() ??
            data['how_to_close']?.toString() ??
            '')
        : (data['suggested_reply']?.toString() ?? '');
    final suggestedReply = draftBodyText;
    final importance = data['importance']?.toString() ?? '';
    final dueDate = data['due_date']?.toString();
    final rawTitle = data['title']?.toString() ?? '';
    final notes = data['notes']?.toString() ?? '';
    final isDone = data['status'] == 'done';
    final outlookMsgId = data['outlook_message_id']?.toString() ?? '';

    // To / CC recipients — stored on the task as arrays by triageEmails,
    // but tolerate a comma-joined string too for older docs.
    List<String> asEmailList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (v is String && v.isNotEmpty) {
        return v.split(RegExp(r'[,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return const <String>[];
    }
    final emailTo = asEmailList(data['email_to']);
    final emailCc = asEmailList(data['email_cc']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarvisTheme.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: JarvisTheme.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildPriorityBadge((data['priority'] ?? 'medium').toString()),
                      _buildActionBadge(actionType, delegateTo),
                      if (importance.isNotEmpty) _buildImportanceBadge(importance),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    rawTitle,
                    style: JarvisTheme.bodyLarge.copyWith(
                      color: JarvisTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (emailFrom.isNotEmpty)
                    _buildContactAwareRow(
                      user: user,
                      label: 'From',
                      value: emailFrom,
                      personName: _matchKnownPerson(emailFrom),
                      taskId: taskId,
                    ),
                  if (emailTo.isNotEmpty)
                    _detailRow('To', _formatRecipients(emailTo)),
                  if (emailCc.isNotEmpty)
                    _detailRow('CC', _formatRecipients(emailCc)),
                  if (emailSubject.isNotEmpty) _detailRow('Subject', emailSubject),
                  if (actionType == 'delegate' && delegateTo.isNotEmpty)
                    _buildContactAwareRow(
                      user: user,
                      label: 'Delegate',
                      value: delegateEmail.isNotEmpty
                          ? '$delegateTo  <$delegateEmail>'
                          : delegateTo,
                      personName: delegateTo,
                      taskId: taskId,
                    ),
                  if (dueDate != null && dueDate.isNotEmpty)
                    _detailRow('Due', AppUtils.formatDate(dueDate)),
                  const SizedBox(height: 14),
                  if (emailSummary.isNotEmpty) ...[
                    _sectionLabel('Email summary'),
                    Text(
                      emailSummary,
                      style: JarvisTheme.bodyMedium.copyWith(
                        color: JarvisTheme.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _sectionLabel(
                    actionType == 'delegate' ? 'What to delegate' : 'What to do',
                  ),
                  Text(
                    howToClose.isNotEmpty
                        ? howToClose
                        : 'No specific steps captured.',
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (suggestedReply.isNotEmpty) ...[
                    _sectionLabel(
                      actionType == 'delegate'
                          ? 'Forward note to ${data['delegate_to'] ?? 'delegate'} (first-person, from you)'
                          : 'Draft reply (first-person)',
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: JarvisTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: JarvisTheme.textMuted.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              suggestedReply,
                              style: JarvisTheme.bodyMedium.copyWith(
                                color: JarvisTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy reply',
                            icon: Icon(
                              Icons.copy,
                              size: 18,
                              color: JarvisTheme.textMuted,
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: suggestedReply),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Reply copied'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // State-aware Outlook draft button — renders OUTSIDE the
                  // suggestedReply block so self-tasks with no reply draft
                  // (e.g. "send team a reminder") and delegate tasks that
                  // rely on how_to_close still get the one-tap draft option.
                  // The button widget handles its own prereq gating
                  // (outlook_message_id, delegate_email).
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.id)
                        .collection('tasks')
                        .doc(taskId)
                        .snapshots(),
                    builder: (ctx, snap) {
                      final live = (snap.data?.data() as Map<String, dynamic>?) ?? data;
                      return _buildOutlookDraftButton(
                        user: user,
                        taskId: taskId,
                        actionType: actionType,
                        outlookMsgId: outlookMsgId,
                        delegateEmail: delegateEmail,
                        draftStatus: live['draft_status']?.toString(),
                        draftId: live['draft_id']?.toString(),
                        draftWeblink: live['draft_weblink']?.toString(),
                        draftError: live['draft_error']?.toString(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (notes.isNotEmpty &&
                      emailSummary.isEmpty &&
                      howToClose.isEmpty) ...[
                    _sectionLabel('Notes'),
                    Text(
                      notes,
                      style: JarvisTheme.bodyMedium.copyWith(
                        color: JarvisTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!isDone)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green,
                              side: const BorderSide(color: Colors.green),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _firestoreService.markTaskDone(user.id, taskId);
                            },
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Mark done'),
                          ),
                        ),
                      if (!isDone) const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: user.accentColor,
                            side: BorderSide(color: user.accentColor),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _showEditTaskSheet(user, taskId, data);
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Compact recipient list — up to 2 full addresses, then "+N more".
  String _formatRecipients(List<String> addrs) {
    if (addrs.isEmpty) return '';
    if (addrs.length <= 2) return addrs.join(', ');
    return '${addrs.take(2).join(', ')}  +${addrs.length - 2} more';
  }

  // State-aware Outlook draft button. Reads draft_status on the task doc:
  //   null/absent             → "Create draft in Outlook" (primary action)
  //   'requested'/'processing' → disabled spinner ("Creating draft…")
  //   'ready'                 → "Open draft in Outlook" (ms-outlook:// deep link)
  //   'error'                 → red Retry button + error line
  // 'requested' = waiting for PA to poll; 'processing' = PA claimed it and
  // is mid-Graph-call. Power Automate writes back the final 'ready'/'error'.
  Widget _buildOutlookDraftButton({
    required UserProfile user,
    required String taskId,
    required String actionType,
    required String outlookMsgId,
    required String delegateEmail,
    required String? draftStatus,
    required String? draftId,
    required String? draftWeblink,
    required String? draftError,
  }) {
    // Prerequisites — if the task predates this feature it won't have an
    // outlook_message_id; Power Automate can't build a threaded draft
    // without it. Delegate forwards additionally need the delegate's email.
    if (outlookMsgId.isEmpty) {
      return _draftButtonStub(
        'Outlook draft unavailable',
        'This email was ingested before 1-click replies launched. Reply directly in Outlook.',
      );
    }
    if (actionType == 'delegate' && delegateEmail.isEmpty) {
      return _draftButtonStub(
        'No email for delegate',
        'Add an email: line for this person in functions/context/user_context.md and redeploy.',
      );
    }

    final label = actionType == 'delegate'
        ? 'Forward in Outlook'
        : 'Reply in Outlook';

    switch (draftStatus) {
      case 'requested':
      case 'processing':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text(
                  draftStatus == 'requested'
                      ? 'Queued — Power Automate picks this up every minute'
                      : 'Creating draft in Outlook… (usually 1–3 minutes)',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: user.accentColor.withOpacity(0.5)),
                  foregroundColor: user.accentColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'It\'s safe to close this — you\'ll get a notification when '
              'the draft is ready. Or check your Outlook Drafts folder.',
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: Icon(Icons.folder_open, size: 16, color: user.accentColor),
                  label: Text(
                    'Open Outlook Drafts',
                    style: TextStyle(color: user.accentColor),
                  ),
                  onPressed: () => _openOutlookDrafts(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _resetDraft(user.id, taskId),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Cancel & retry',
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textMuted),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'ready':
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openOutlookDraft(draftId, draftWeblink),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(
              actionType == 'delegate'
                  ? 'Open forward in Outlook'
                  : 'Open draft in Outlook',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: user.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        );
      case 'error':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((draftError ?? '').isNotEmpty) ...[
              Text(
                draftError!,
                style: JarvisTheme.bodySmall.copyWith(color: Colors.orange.shade300),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openOutlookDrafts,
                    icon: Icon(Icons.folder_open, size: 16, color: user.accentColor),
                    label: Text(
                      'Check Drafts',
                      style: TextStyle(color: user.accentColor),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: user.accentColor.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _firestoreService.requestOutlookDraft(user.id, taskId),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: user.accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      default:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                await _firestoreService.requestOutlookDraft(user.id, taskId);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to request draft: $e')),
                );
              }
            },
            icon: Icon(
              actionType == 'delegate' ? Icons.forward : Icons.reply,
              size: 18,
            ),
            label: Text(label),
            style: ElevatedButton.styleFrom(
              backgroundColor: user.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        );
    }
  }

  // Disabled-button placeholder with a short explanation below.
  Widget _draftButtonStub(String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.info_outline, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
        ),
      ],
    );
  }

  // Open the Outlook Drafts folder — used from the spinner UI so users
  // can check if the draft already landed while PA's callback is lagging.
  Future<void> _openOutlookDrafts() async {
    // ms-outlook deep link to Drafts folder
    final uri = Uri.parse('ms-outlook://mail/drafts');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        // Fallback: Outlook web drafts
        final webUri = Uri.parse('https://outlook.office.com/mail/drafts');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Outlook: $e')),
      );
    }
  }

  // Clear draft_* fields on a task (used by the "Cancel and reset" action
  // under the spinner). Called when PA is stuck and the user wants out.
  Future<void> _resetDraft(String userId, String taskId) async {
    try {
      await _firestoreService.resetOutlookDraft(userId, taskId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft reset. Tap again to retry.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $e')),
      );
    }
  }

  // Launch the Outlook mobile draft. Prefer the ms-outlook:// deep link;
  // fall back to the Graph weblink if the app isn't installed.
  Future<void> _openOutlookDraft(String? draftId, String? weblink) async {
    Future<bool> tryLaunch(Uri uri) async {
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }

    if (draftId != null && draftId.isNotEmpty) {
      final uri = Uri.parse('ms-outlook://compose?draftId=${Uri.encodeComponent(draftId)}');
      if (await tryLaunch(uri)) return;
    }
    if (weblink != null && weblink.isNotEmpty) {
      final uri = Uri.parse(weblink);
      if (await tryLaunch(uri)) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Outlook — install the app or check the weblink.')),
    );
  }

  Future<void> _bulkDeleteTasks(String userId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: JarvisTheme.surface2,
          title: Text(
            'Delete Tasks',
            style: JarvisTheme.bodyLarge.copyWith(color: JarvisTheme.textPrimary),
          ),
          content: Text(
            'Delete ${_selectedTaskIds.length} task${_selectedTaskIds.length > 1 ? 's' : ''}? This cannot be undone.',
            style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Delete',
                style: JarvisTheme.bodyMedium.copyWith(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (result == true) {
      try {
        for (final taskId in _selectedTaskIds) {
          await _firestoreService.deleteTask(userId, taskId);
        }
        setState(() {
          _selectedTaskIds.clear();
          _isSelectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tasks deleted successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete tasks: $e')),
        );
      }
    }
  }

  Widget _buildHabitsSection(UserProfile user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('recurring_tasks')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final habits = snapshot.data!.docs;
        
        if (habits.isEmpty) {
          return _buildEmptyState('No habits yet. Tap + to create one.');
        }
        
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: habits.length,
          itemBuilder: (context, index) {
            final habit = habits[index];
            final data = habit.data() as Map<String, dynamic>;
            return _buildDismissibleHabitCard(user, habit.id, data);
          },
        );
      },
    );
  }

  Widget _buildDismissibleHabitCard(UserProfile user, String habitId, Map<String, dynamic> data) {
    return Dismissible(
      key: Key('habit_$habitId'),
      direction: DismissDirection.horizontal,
      background: Container(
        color: Colors.blue.withOpacity(0.7),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red.withOpacity(0.7),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showEditHabitSheet(user, habitId, data);
          return false;
        } else {
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: JarvisTheme.surface2,
              title: Text('Delete Habit', style: JarvisTheme.bodyLarge.copyWith(color: JarvisTheme.textPrimary)),
              content: Text('Delete this habit?', style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textSecondary)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Delete', style: JarvisTheme.bodyMedium.copyWith(color: Colors.red)),
                ),
              ],
            ),
          );
          if (result == true) {
            await _firestoreService.deleteRecurringTask(user.id, habitId);
            return true;
          }
          return false;
        }
      },
      onDismissed: (_) {},
      child: _buildHabitCard(user, habitId, data),
    );
  }

  void _showEditHabitSheet(UserProfile user, String habitId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditHabitBottomSheet(
        habitId: habitId,
        habitData: data,
        onHabitUpdated: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildHabitCard(UserProfile user, String habitId, Map<String, dynamic> data) {
    final isActive = data['active'] ?? false;
    final frequency = data['frequency'] ?? 'daily';
    final timeOfDay = data['time_of_day']?.toString();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Frequency badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: user.accentColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              frequency.toUpperCase(),
              style: JarvisTheme.bodySmall.copyWith(
                color: user.accentColor,
                fontSize: 10,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Habit details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] ?? 'Untitled Habit',
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: JarvisTheme.textPrimary,
                  ),
                ),
                
                if (timeOfDay != null)
                  const SizedBox(height: 4),
                
                if (timeOfDay != null)
                  Text(
                    timeOfDay,
                    style: JarvisTheme.bodySmall.copyWith(
                      color: JarvisTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          
          // Active toggle
          Switch(
            value: isActive,
            activeColor: user.accentColor,
            onChanged: (value) {
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.id)
                  .collection('recurring_tasks')
                  .doc(habitId)
                  .update({'active': value});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThoughtsSection(UserProfile user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('thoughts')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final thoughts = snapshot.data!.docs;
        
        if (thoughts.isEmpty) {
          return _buildEmptyState('No thoughts saved yet.');
        }
        
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: thoughts.length,
          itemBuilder: (context, index) {
            final thought = thoughts[index];
            final data = thought.data() as Map<String, dynamic>;
            return _buildThoughtCard(user, data, thought.id);
          },
        );
      },
    );
  }

  void _showEditThoughtDialog(UserProfile user, String thoughtId, Map<String, dynamic> data) {
    final titleCtrl = TextEditingController(text: data['title'] ?? '');
    final contentCtrl = TextEditingController(text: data['content'] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JarvisTheme.surface,
        title: Text('Edit Thought', style: JarvisTheme.bodyLarge.copyWith(color: JarvisTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Title',
                labelStyle: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Content',
                labelStyle: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirestoreService().updateThought(user.id, thoughtId, {
                'title': titleCtrl.text.trim(),
                'content': contentCtrl.text.trim(),
              });
            },
            child: Text('Save', style: TextStyle(color: user.accentColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildThoughtCard(UserProfile user, Map<String, dynamic> data, String thoughtId) {
    final title = data['title'] ?? 'Untitled Thought';
    final content = data['content'] ?? '';
    final category = data['category']?.toString();
    final rawTs = data['created_at'];
    final createdDate = rawTs is Timestamp
        ? AppUtils.formatDateFromDateTime(rawTs.toDate())
        : rawTs?.toString();
    final isExpanded = _expandedThoughtId == thoughtId;

    return GestureDetector(
      onTap: () => setState(() {
        _expandedThoughtId = isExpanded ? null : thoughtId;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: JarvisTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: isExpanded
              ? Border.all(color: user.accentColor.withOpacity(0.3), width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 16, color: JarvisTheme.textMuted),
                  color: JarvisTheme.surface2,
                  onSelected: (val) async {
                    if (val == 'edit') {
                      _showEditThoughtDialog(user, thoughtId, data);
                    } else if (val == 'delete') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: JarvisTheme.surface,
                          title: Text('Delete Thought', style: JarvisTheme.bodyLarge.copyWith(color: JarvisTheme.textPrimary)),
                          content: Text('Delete "$title"?', style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textSecondary)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await FirestoreService().deleteThought(user.id, thoughtId);
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            AnimatedCrossFade(
              firstChild: Text(
                content.length > 100 ? '${content.substring(0, 100)}...' : content,
                style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              secondChild: Text(
                content,
                style: JarvisTheme.bodySmall.copyWith(color: JarvisTheme.textSecondary),
              ),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),

            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: user.accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      category,
                      style: JarvisTheme.bodySmall.copyWith(
                        color: user.accentColor,
                        fontSize: 10,
                      ),
                    ),
                  )
                else
                  const SizedBox(),

                if (createdDate != null)
                  Text(
                    createdDate,
                    style: JarvisTheme.bodySmall.copyWith(
                      color: JarvisTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceSection(UserProfile user) {
    final async = ref.watch(financeEntriesProvider(user.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildFinanceEmptyState(),
      data: (entries) {
        if (entries.isEmpty) return _buildFinanceEmptyState();
        final snap = ref.watch(netWorthSnapshotProvider(user.id));
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month, 1);
        final monthEntries =
            entries.where((e) => !e.date.isBefore(monthStart)).toList();
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildNetWorthHero(user, snap),
            const SizedBox(height: 16),
            _buildAllocationList(user, snap),
            const SizedBox(height: 20),
            _buildMonthEntriesHeader(now),
            const SizedBox(height: 8),
            if (monthEntries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No entries this month yet.',
                  style: JarvisTheme.bodySmall
                      .copyWith(color: JarvisTheme.textMuted),
                ),
              )
            else
              for (final e in monthEntries.take(8)) _buildEntryRow(user, e),
          ],
        );
      },
    );
  }

  Widget _buildNetWorthHero(UserProfile user, NetWorthSnapshot snap) {
    final accent = user.accentColor;
    final totalStr = _formatInr(snap.total);
    final deltaStr = snap.deltaPct >= 0
        ? '▲ ${snap.deltaPct.toStringAsFixed(1)}% MoM'
        : '▼ ${snap.deltaPct.abs().toStringAsFixed(1)}% MoM';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisTheme.surface2, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET WORTH · LIQUID',
            style: JarvisTheme.bodySmall.copyWith(
              color: JarvisTheme.textMuted,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            totalStr,
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 34,
              color: JarvisTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            deltaStr,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _buildStackedAllocationBar(snap),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparklinePainter(
                values: snap.sparkline,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedAllocationBar(NetWorthSnapshot snap) {
    if (snap.total == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: JarvisTheme.surface2,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final b in snap.allocation)
              Expanded(
                flex: (b.percent * 100).round().clamp(1, 10000),
                child: Container(
                  color: _allocationColor(b.category),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllocationList(UserProfile user, NetWorthSnapshot snap) {
    if (snap.allocation.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JarvisTheme.surface2, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < snap.allocation.length; i++) ...[
            _buildAllocationRow(user, snap.allocation[i]),
            if (i != snap.allocation.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(height: 1, color: JarvisTheme.surface2),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllocationRow(UserProfile user, AllocationBucket b) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 34,
          decoration: BoxDecoration(
            color: _allocationColor(b.category),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            b.category,
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatInr(b.amount),
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 18,
                color: JarvisTheme.textPrimary,
              ),
            ),
            Text(
              '${b.percent.toStringAsFixed(1)}%',
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthEntriesHeader(DateTime now) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return Row(
      children: [
        Text(
          '${monthNames[now.month - 1]} entries',
          style: const TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 22,
            color: JarvisTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildEntryRow(UserProfile user, Finance e) {
    final dayNum = e.date.day.toString().padLeft(2, '0');
    const monShort = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: JarvisTheme.surface2, width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayNum,
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 20,
                    color: JarvisTheme.textPrimary,
                  ),
                ),
                Text(
                  monShort[e.date.month - 1],
                  style: JarvisTheme.bodySmall.copyWith(
                    color: JarvisTheme.textMuted,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.description.isEmpty ? 'Entry' : e.description,
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: JarvisTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  e.category.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 10,
                    color: user.accentColor,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatInr(e.amount),
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 18,
              color: JarvisTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Color _allocationColor(String category) {
    switch (category.toLowerCase()) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'stocks':
      case 'stock':
        return const Color(0xFF4CAF50);
      case 'mf':
      case 'mutualfund':
      case 'mutual fund':
        return const Color(0xFF2196F3);
      case 'savings':
        return const Color(0xFFE8A045);
      default:
        return JarvisTheme.textSecondary;
    }
  }

  String _formatInr(double amount) {
    final rounded = amount.round();
    if (rounded == 0) return '₹ 0';
    final s = rounded.abs().toString();
    // Indian grouping: last 3 digits, then groups of 2.
    String withCommas;
    if (s.length <= 3) {
      withCommas = s;
    } else {
      final last3 = s.substring(s.length - 3);
      final rest = s.substring(0, s.length - 3);
      final buf = StringBuffer();
      for (var i = 0; i < rest.length; i++) {
        buf.write(rest[i]);
        final remaining = rest.length - 1 - i;
        if (remaining > 0 && remaining % 2 == 0) buf.write(',');
      }
      withCommas = '$buf,$last3';
    }
    final sign = rounded < 0 ? '-' : '';
    return '$sign₹ $withCommas';
  }

  Widget _buildGoalsSection(UserProfile user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('goals')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data!.docs;

        // Empty state — offer the HVAC roadmap import + add simple goal
        if (allDocs.isEmpty) {
          return _buildGoalsEmptyState(user);
        }

        // Split into roadmap goals and simple goals
        final roadmapGoals = <QueryDocumentSnapshot>[];
        final simpleGoals = <QueryDocumentSnapshot>[];
        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final type = (data['type'] ?? 'simple').toString();
          if (type == 'roadmap') {
            roadmapGoals.add(doc);
          } else {
            simpleGoals.add(doc);
          }
        }

        // Apply filter
        bool matchesFilter(Map<String, dynamic> data) {
          final status = (data['status'] ?? 'active').toString();
          switch (_goalFilter) {
            case 'active':
              return status == 'active';
            case 'done':
              return status == 'done';
            case 'all':
            default:
              return true;
          }
        }

        final roadmapFiltered = roadmapGoals
            .where((d) => matchesFilter(d.data() as Map<String, dynamic>))
            .toList();
        final simpleFiltered = simpleGoals
            .where((d) => matchesFilter(d.data() as Map<String, dynamic>))
            .toList();

        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildGoalsFilterBar(user, roadmapGoals.isEmpty),
            const SizedBox(height: 12),
            if (roadmapFiltered.isEmpty && simpleFiltered.isEmpty)
              _buildEmptyState('No goals match this filter.'),
            for (final doc in roadmapFiltered)
              _buildRoadmapHeroCard(
                user,
                Goal.fromDoc(
                  doc as DocumentSnapshot<Map<String, dynamic>>,
                  user.id,
                ),
              ),
            if (roadmapFiltered.isNotEmpty && simpleFiltered.isNotEmpty)
              const SizedBox(height: 8),
            for (final doc in simpleFiltered)
              _buildGoalCard(
                user,
                doc.data() as Map<String, dynamic>,
                doc.id,
              ),
          ],
        );
      },
    );
  }

  // Filter chips + "Import roadmap" shortcut when no roadmap exists yet.
  Widget _buildGoalsFilterBar(UserProfile user, bool noRoadmap) {
    Widget chip(String label, String value) {
      final selected = _goalFilter == value;
      return GestureDetector(
        onTap: () => setState(() => _goalFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? user.accentColor.withOpacity(0.22)
                : JarvisTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? user.accentColor.withOpacity(0.6)
                  : JarvisTheme.surface2,
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: JarvisTheme.bodySmall.copyWith(
              color: selected ? user.accentColor : JarvisTheme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('All', 'all'),
        const SizedBox(width: 8),
        chip('Active', 'active'),
        const SizedBox(width: 8),
        chip('Done', 'done'),
        const Spacer(),
        if (noRoadmap)
          TextButton.icon(
            onPressed: _isSeedingRoadmap ? null : () => _seedHvacRoadmap(user),
            icon: Icon(Icons.auto_awesome,
                size: 16, color: user.accentColor),
            label: Text(
              _isSeedingRoadmap ? 'Importing…' : 'Import HVAC',
              style: JarvisTheme.bodySmall
                  .copyWith(color: user.accentColor, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }

  Widget _buildGoalsEmptyState(UserProfile user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Column(
        children: [
          Icon(Icons.track_changes,
              size: 56, color: user.accentColor.withOpacity(0.7)),
          const SizedBox(height: 16),
          Text(
            'Import your growth roadmap',
            style: JarvisTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Bring in the 24-month AI-HVAC sales leadership plan and tick off '
              'each checkpoint as you go. Or start with a simple goal.',
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isSeedingRoadmap ? null : () => _seedHvacRoadmap(user),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(
              _isSeedingRoadmap ? 'Importing…' : 'Import HVAC Roadmap',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: user.accentColor,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _seedHvacRoadmap(UserProfile user) async {
    setState(() => _isSeedingRoadmap = true);
    try {
      final goalId =
          await FirestoreService().seedHvacRoadmap(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('HVAC roadmap imported.')),
      );
      // Open straight into the drilldown so Pallav sees all 47 items.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoadmapDetailScreen(user: user, goalId: goalId),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeedingRoadmap = false);
    }
  }

  // ─────────────────── ROADMAP HERO CARD ────────────────────────────────────
  Widget _buildRoadmapHeroCard(UserProfile user, Goal goal) {
    final accent = user.accentColor;
    final progress = goal.overallProgress;
    final phase = goal.currentPhase;
    final nextUp = goal.nextUp(limit: 3);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withOpacity(0.35),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RoadmapDetailScreen(user: user, goalId: goal.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: icon + title + ⋮ menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag, color: accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.title,
                            style: JarvisTheme.bodyLarge
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          if (phase != null)
                            Text(
                              'Phase ${goal.currentPhaseIndex + 1} of ${goal.phases.length}'
                              ' · ${phase.title} · ${phase.monthsLabel}',
                              style: JarvisTheme.bodySmall
                                  .copyWith(color: JarvisTheme.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    _buildRoadmapMenu(user, goal),
                  ],
                ),
                const SizedBox(height: 14),
                // Ring + bar + caption
                Row(
                  children: [
                    _HeroProgressRing(
                      progress: progress, color: accent, size: 58),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: JarvisTheme.surface2,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor:
                                  (progress / 100).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${goal.doneCheckpoints} of ${goal.totalCheckpoints} checkpoints done',
                            style: JarvisTheme.bodySmall
                                .copyWith(color: JarvisTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (nextUp.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Next up',
                    style: JarvisTheme.labelMedium
                        .copyWith(color: JarvisTheme.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  for (final cp in nextUp)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.radio_button_unchecked,
                              size: 14, color: JarvisTheme.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              cp.title,
                              style: JarvisTheme.bodySmall.copyWith(
                                color: JarvisTheme.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RoadmapDetailScreen(
                                  user: user, goalId: goal.id),
                            ),
                          );
                        },
                        icon:
                            const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open roadmap'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: goal.hasAttachment
                            ? () => _openGoalAttachment(goal.attachmentUrl!)
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RoadmapDetailScreen(
                                        user: user, goalId: goal.id),
                                  ),
                                );
                              },
                        icon: Icon(
                          goal.hasAttachment
                              ? Icons.description
                              : Icons.upload_file,
                          size: 16,
                          color: accent,
                        ),
                        label: Text(
                          goal.hasAttachment ? 'View .docx' : 'Attach doc',
                          style: TextStyle(color: accent),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: accent.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoadmapMenu(UserProfile user, Goal goal) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          size: 18, color: JarvisTheme.textMuted),
      color: JarvisTheme.surface2,
      onSelected: (val) async {
        if (val == 'mark_paused') {
          await FirestoreService().updateGoal(
              user.id, goal.id, {'status': 'paused'});
        } else if (val == 'mark_active') {
          await FirestoreService().updateGoal(
              user.id, goal.id, {'status': 'active'});
        } else if (val == 'delete') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: JarvisTheme.surface,
              title: Text('Delete roadmap?',
                  style: JarvisTheme.bodyLarge),
              content: Text(
                'This removes "${goal.title}" and all its checkpoints. '
                'The attached document (if any) stays in Storage.',
                style: JarvisTheme.bodyMedium
                    .copyWith(color: JarvisTheme.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await FirestoreService().deleteGoal(user.id, goal.id);
          }
        }
      },
      itemBuilder: (_) => [
        if (goal.status == 'active')
          const PopupMenuItem(
            value: 'mark_paused',
            child: Row(children: [
              Icon(Icons.pause_circle_outline, size: 16),
              SizedBox(width: 8),
              Text('Mark paused'),
            ]),
          ),
        if (goal.status != 'active')
          const PopupMenuItem(
            value: 'mark_active',
            child: Row(children: [
              Icon(Icons.play_circle_outline, size: 16),
              SizedBox(width: 8),
              Text('Resume'),
            ]),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    );
  }

  Future<void> _openGoalAttachment(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open document.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open failed: $e')),
        );
      }
    }
  }

  Widget _buildGoalCard(UserProfile user, Map<String, dynamic> data, String goalId) {
    final title = data['title'] ?? 'Untitled Goal';
    final progress = (data['progress'] ?? 0).toDouble();
    final deadline = data['deadline']?.toString();
    final status = data['status'] ?? 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: JarvisTheme.bodySmall.copyWith(color: _getStatusColor(status), fontSize: 10),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 16, color: JarvisTheme.textMuted),
                color: JarvisTheme.surface2,
                onSelected: (val) async {
                  if (val == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: JarvisTheme.surface,
                        title: Text('Delete Goal', style: JarvisTheme.bodyLarge.copyWith(color: JarvisTheme.textPrimary)),
                        content: Text('Delete "$title"?', style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await FirestoreService().deleteGoal(user.id, goalId);
                    }
                  } else if (val == 'mark_done') {
                    await FirestoreService().updateGoal(user.id, goalId, {'status': 'done', 'progress': 100});
                  } else if (val == 'mark_active') {
                    await FirestoreService().updateGoal(user.id, goalId, {'status': 'active'});
                  }
                },
                itemBuilder: (_) => [
                  if (status != 'done')
                    const PopupMenuItem(value: 'mark_done', child: Row(children: [Icon(Icons.check_circle, size: 16, color: Colors.green), SizedBox(width: 8), Text('Mark Done')])),
                  if (status == 'done')
                    const PopupMenuItem(value: 'mark_active', child: Row(children: [Icon(Icons.refresh, size: 16), SizedBox(width: 8), Text('Reactivate')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Progress bar
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: JarvisTheme.surface2,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: user.accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.toInt()}%',
                style: JarvisTheme.bodySmall.copyWith(
                  color: JarvisTheme.textMuted,
                ),
              ),
              
              if (deadline != null)
                Text(
                  AppUtils.formatDate(deadline),
                  style: JarvisTheme.bodySmall.copyWith(
                    color: JarvisTheme.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'paused':
        return Colors.orange;
      case 'done':
        return Colors.blue;
      default:
        return JarvisTheme.textMuted;
    }
  }

  // _buildMealsSection removed — now delegated to MealsSection widget
  // (see meals/meals_section.dart). The case in _buildSectionContent
  // instantiates MealsSection(user: user) directly.

  Widget _buildFinanceEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Text(
              'No finance entries yet',
              style: JarvisTheme.bodyMedium.copyWith(
                color: JarvisTheme.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                widget.onSwitchToChat?.call();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add your first investment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: JarvisTheme.surface2,
                foregroundColor: JarvisTheme.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          style: JarvisTheme.bodyMedium.copyWith(
            color: JarvisTheme.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSelectionToolbar(UserProfile user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: JarvisTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: user.accentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedTaskIds.length} selected',
            style: JarvisTheme.bodyMedium.copyWith(
              color: JarvisTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _bulkDeleteTasks(user.id),
            icon: const Icon(Icons.delete, color: Colors.red),
            label: Text(
              'Delete',
              style: JarvisTheme.bodyMedium.copyWith(color: Colors.red),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedTaskIds.clear();
                _isSelectionMode = false;
              });
            },
            child: Text(
              'Cancel',
              style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTaskSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddTaskBottomSheet(
          onTaskAdded: () {
            Navigator.pop(context);
          },
        );
      },
    );
  }

  void _showAddThoughtSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddThoughtBottomSheet(
        onThoughtAdded: () => Navigator.pop(context),
      ),
    );
  }

  void _showAddHabitSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddHabitBottomSheet(
        onHabitAdded: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final user = ref.watch(activeUserProvider);

    if (user == null) {
      return Scaffold(
        backgroundColor: JarvisTheme.background,
        body: const Center(
          child: Text('Please login first'),
        ),
      );
    }

    // Fix for the web-blank-board race: if auth resolved after initState
    // ran, pull the section list in now. Cheap list equality — bails if
    // we already have the right sections, so normal rebuilds don't loop.
    if (_userSections.length != user.boardSections.length ||
        !_listEquals(_userSections, user.boardSections)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadUserSections();
      });
    }

    return Scaffold(
      backgroundColor: JarvisTheme.background,
      floatingActionButton: !_isSelectionMode && _userSections.isNotEmpty
          ? () {
              final currentSection = _userSections[_selectedSectionIndex];
              if (currentSection == 'Tasks') {
                return FloatingActionButton(
                  onPressed: _showAddTaskSheet,
                  backgroundColor: user.accentColor,
                  child: const Icon(Icons.add, color: Colors.white),
                );
              } else if (currentSection == 'Habits') {
                return FloatingActionButton(
                  onPressed: _showAddHabitSheet,
                  backgroundColor: user.accentColor,
                  child: const Icon(Icons.add, color: Colors.white),
                );
              } else if (currentSection == 'Thoughts') {
                return FloatingActionButton(
                  onPressed: _showAddThoughtSheet,
                  backgroundColor: user.accentColor,
                  child: const Icon(Icons.edit_note, color: Colors.white),
                );
              }
              return null;
            }()
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        bottom: true,
        child: _BoardSwipeWrapper(
          sectionCount: _userSections.length,
          selectedIndex: _selectedSectionIndex,
          accentColor: user.accentColor,
          onSwipeLeft: () {
            if (_selectedSectionIndex < _userSections.length - 1) {
              FocusScope.of(context).unfocus();
              setState(() => _selectedSectionIndex++);
              widget.sectionNotifier?.value = _selectedSectionIndex;
            }
          },
          onSwipeRight: () {
            if (_selectedSectionIndex > 0) {
              FocusScope.of(context).unfocus();
              setState(() => _selectedSectionIndex--);
              widget.sectionNotifier?.value = _selectedSectionIndex;
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: JarvisTheme.lg,
              right: JarvisTheme.lg,
              top: JarvisTheme.lg,
              bottom: 120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreetingSection(user),

                const SizedBox(height: 24),

                // Selection toolbar
                if (_isSelectionMode)
                  _buildSelectionToolbar(user),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_selectedSectionIndex),
                    child: _buildSectionContent(user),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps board content with drag-aware horizontal swipe that shows visual feedback
class _BoardSwipeWrapper extends StatefulWidget {
  final int sectionCount;
  final int selectedIndex;
  final Color accentColor;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final Widget child;

  const _BoardSwipeWrapper({
    required this.sectionCount,
    required this.selectedIndex,
    required this.accentColor,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.child,
  });

  @override
  State<_BoardSwipeWrapper> createState() => _BoardSwipeWrapperState();
}

class _BoardSwipeWrapperState extends State<_BoardSwipeWrapper> {
  double _dragOffset = 0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Clamp drag to max 30% of screen
    final clampedOffset = _dragOffset.clamp(-screenWidth * 0.3, screenWidth * 0.3);

    return GestureDetector(
      onHorizontalDragStart: (_) {
        setState(() => _isDragging = true);
      },
      onHorizontalDragUpdate: (details) {
        setState(() => _dragOffset += details.delta.dx);
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        // Require deliberate intent — either a fast flick OR a long drag.
        // Previously 15% + 200 velocity triggered on accidental small drags
        // while scrolling vertically. New thresholds (25% OR 600 velocity)
        // take a clear commitment to switch tabs.
        const minVelocity = 600.0;
        final minDistance = screenWidth * 0.25;
        final swipeLeft = velocity < -minVelocity || _dragOffset < -minDistance;
        final swipeRight = velocity > minVelocity || _dragOffset > minDistance;
        if (swipeLeft) {
          widget.onSwipeLeft();
        } else if (swipeRight) {
          widget.onSwipeRight();
        }
        setState(() {
          _dragOffset = 0;
          _isDragging = false;
        });
      },
      onHorizontalDragCancel: () {
        setState(() {
          _dragOffset = 0;
          _isDragging = false;
        });
      },
      child: Stack(
        children: [
          // Content with drag offset
          AnimatedContainer(
            duration: _isDragging ? Duration.zero : const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(clampedOffset * 0.3, 0, 0),
            child: AnimatedOpacity(
              duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
              opacity: _isDragging ? (1.0 - (clampedOffset.abs() / screenWidth) * 0.4) : 1.0,
              child: widget.child,
            ),
          ),
          // Swipe direction indicator — only appears when the drag is past
          // the commit threshold so the user learns the new, tighter range.
          if (_isDragging && clampedOffset.abs() > screenWidth * 0.12)
            Positioned(
              top: 0,
              bottom: 0,
              left: clampedOffset > 0 ? 0 : null,
              right: clampedOffset < 0 ? 0 : null,
              child: Center(
                child: AnimatedOpacity(
                  duration: Duration.zero,
                  opacity: (clampedOffset.abs() / (screenWidth * 0.25)).clamp(0.0, 0.8),
                  child: Container(
                    width: 4,
                    height: 60,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddHabitBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback onHabitAdded;

  const _AddHabitBottomSheet({required this.onHabitAdded});

  @override
  ConsumerState<_AddHabitBottomSheet> createState() => _AddHabitBottomSheetState();
}

class _AddHabitBottomSheetState extends ConsumerState<_AddHabitBottomSheet> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  String _selectedFrequency = AppConstants.recurringFrequencies.first;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final user = ref.read(activeUserProvider);
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _firestoreService.createRecurringTask(user.id, {
        'title': title,
        'frequency': _selectedFrequency,
        'time_of_day': _timeController.text.trim().isEmpty ? null : _timeController.text.trim(),
        'active': true,
      });
      widget.onHabitAdded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating habit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final user = ref.watch(activeUserProvider);
    final accentColor = user?.accentColor ?? JarvisTheme.pallavAccent;

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
                'New Habit',
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
              hintText: 'Habit name (e.g. Morning workout)',
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
                    color: isSelected ? accentColor.withOpacity(0.2) : JarvisTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? accentColor : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    freq,
                    style: JarvisTheme.bodySmall.copyWith(
                      color: isSelected ? accentColor : JarvisTheme.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _timeController,
            style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Time of day (e.g. 7:00 AM)',
              hintStyle: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textMuted),
              filled: true,
              fillColor: JarvisTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: Icon(Icons.schedule, color: JarvisTheme.textMuted, size: 18),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
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
                      'Create Habit',
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

// Small % ring used on the roadmap hero card. Standalone so we don't reach
// into MotivationRing (which hardcodes completed/total labels).
class _HeroProgressRing extends StatelessWidget {
  final double progress; // 0..100
  final Color color;
  final double size;

  const _HeroProgressRing({
    required this.progress,
    required this.color,
    this.size = 58,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _HeroRingPainter(
              progress: 1,
              color: JarvisTheme.surface2,
              strokeWidth: 6,
            ),
          ),
          if (progress > 0)
            CustomPaint(
              size: Size(size, size),
              painter: _HeroRingPainter(
                progress: (progress / 100).clamp(0.0, 1.0),
                color: color,
                strokeWidth: 6,
              ),
            ),
          Text(
            '${progress.toInt()}%',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: size * 0.28,
              fontWeight: FontWeight.w600,
              color: JarvisTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _HeroRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * 3.14159265 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159265 / 2,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HeroRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.01 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - ((values[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = color.withOpacity(0.14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final lastX = (values.length - 1) * dx;
    final lastY = size.height - ((values.last - minV) / range) * size.height;
    canvas.drawCircle(Offset(lastX, lastY), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}
