import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../widgets/jarvis_logo.dart';
import '../widgets/user_avatar.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/widget_action_provider.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../models/user_profile.dart';
import './chat/chat_screen.dart';
import './board/board_screen.dart';
import './settings/settings_screen.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  late NotificationService _notificationService;
  late PageController _pageController;
  final ValueNotifier<bool> _isRoseMode = ValueNotifier(false);
  final ValueNotifier<int> _boardSectionIndex = ValueNotifier(0);
  StreamSubscription<Uri?>? _widgetClickSub;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService();
    _pageController = PageController();
    _screens = [
      ChatScreen(
        isRoseModeNotifier: _isRoseMode,
      ),
      BoardScreen(
        sectionNotifier: _boardSectionIndex,
        onSwitchToChat: () => _onItemTapped(0),
      ),
    ];
    _isRoseMode.addListener(_onRoseModeChanged);
    _boardSectionIndex.addListener(_onBoardSectionChanged);
    // Subscribe to AppLifecycleState changes so we can drain the widget
    // URI queue whenever the app returns to the foreground (warm-start
    // widget taps).
    WidgetsBinding.instance.addObserver(this);
    _initializeNotificationService();
    // Defer widget listener setup until after the first frame. Calling
    // _pageController.animateToPage (indirectly via _handleWidgetUri) on
    // a controller that hasn't attached to its PageView yet throws, and
    // that was suspected in the "board crashes when widget enabled" bug.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initHomeWidgetListeners();
      // Prime the widget with fresh task counts so it doesn't sit at
      // "0 of 0" until the user visits the board tab. One-shot fetch,
      // fire-and-forget, never throws.
      _primeHomeWidget();
    });
  }

  /// One-shot task count push so the widget shows real numbers as soon
  /// as the app opens (not stale zeros from a prior session or from the
  /// widget's own default-state render). Fully guarded — a Firestore
  /// error must never bubble into initState.
  Future<void> _primeHomeWidget() async {
    try {
      final userId = ref.read(activeUserIdProvider);
      if (userId == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks')
          .get();
      await HomeWidgetService.pushFromSnapshot(snap);
    } catch (e) {
      debugPrint('_primeHomeWidget failed (non-fatal): $e');
    }
  }

  // MethodChannel for widget taps. Matches MainActivity.kt's CHANNEL
  // constant. MainActivity is purely a pull-based queue — we drain it
  // on init (cold-start URIs) and again after every resume (warm-start
  // URIs). No push-based invokeMethod from Kotlin to avoid the race
  // where the channel is registered but HomeScreen hasn't subscribed yet.
  static const _widgetChannel = MethodChannel('com.pallav.jarvis/widget');

  // Brief polling window after app resume to catch warm-start widget
  // taps. onNewIntent fires on MainActivity, URI lands in the queue,
  // AppLifecycleState.resumed fires here, we drain.
  Timer? _resumeDrainTimer;

  /// Home-widget taps arrive as jarvis:// URIs. Route them to the chat
  /// screen with the right signal so ChatScreen auto-focuses input or
  /// starts voice recording.
  ///
  /// Every plugin call is guarded — if something throws on this device,
  /// we silently continue rather than crash the app.
  Future<void> _initHomeWidgetListeners() async {
    // Primary path: drain MainActivity's pending URI queue. Loops until
    // the queue is empty so we catch any backlog (e.g. multiple taps
    // before Flutter came up).
    await _drainWidgetQueue();
    // Fallback path: home_widget's stream, in case a future version
    // routes intents that don't hit our MainActivity path.
    try {
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null && mounted) _handleWidgetUri(initialUri);
    } catch (e) {
      debugPrint('HomeWidget initiallyLaunched failed: $e');
    }
    try {
      _widgetClickSub = HomeWidget.widgetClicked.listen(
        (uri) {
          if (uri != null && mounted) _handleWidgetUri(uri);
        },
        onError: (Object e) {
          debugPrint('HomeWidget click stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('HomeWidget widgetClicked subscribe failed: $e');
    }
  }

  /// Drain all queued widget URIs from MainActivity. Pull one at a time
  /// until the queue returns null.
  Future<void> _drainWidgetQueue() async {
    // Hard cap on drain iterations to prevent an infinite loop if
    // something goes wrong on the native side.
    for (int i = 0; i < 16; i++) {
      try {
        final uri = await _widgetChannel.invokeMethod<String?>(
          'consumePendingUri',
        );
        if (uri == null) return;
        if (!mounted) return;
        _handleWidgetUri(Uri.parse(uri));
      } catch (e) {
        debugPrint('drainWidgetQueue iter $i failed: $e');
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Poll the queue briefly after resume. onNewIntent runs slightly
      // before AppLifecycleState.resumed fires, so drain a few times
      // to be safe.
      _resumeDrainTimer?.cancel();
      int ticks = 0;
      _resumeDrainTimer = Timer.periodic(const Duration(milliseconds: 250),
          (t) async {
        ticks++;
        if (ticks > 8 || !mounted) {
          t.cancel();
          return;
        }
        await _drainWidgetQueue();
      });
    }
  }

  void _handleWidgetUri(Uri uri) {
    // Supported shapes:
    //   jarvis://chat   → host is 'chat'   → chat tab + focus keyboard
    //   jarvis://voice  → host is 'voice'  → chat tab + start recording
    //   jarvis://tasks  → host is 'tasks'  → board tab (tasks view)
    final target = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    if (target == 'tasks') {
      _onItemTapped(1); // board tab — no widget action needed, just jump there
      return;
    }
    // Chat / voice: switch to chat tab first.
    _onItemTapped(0);
    // Write the pending action into Riverpod state. ChatScreen watches
    // this provider and acts on 'chat'/'voice' — survives rebuilds and
    // doesn't care about timing like a ValueNotifier bump did.
    if (target == 'chat' || target == 'voice') {
      ref.read(widgetActionProvider.notifier).state = target;
    }
  }

  void _onRoseModeChanged() {
    if (mounted) setState(() {});
  }

  void _onBoardSectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _resumeDrainTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _notificationService.dispose();
    _pageController.dispose();
    _widgetClickSub?.cancel();
    _isRoseMode.removeListener(_onRoseModeChanged);
    _boardSectionIndex.removeListener(_onBoardSectionChanged);
    _isRoseMode.dispose();
    _boardSectionIndex.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _initializeNotificationService() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('active_user');

    if (userId != null && userId.isNotEmpty) {
      await _notificationService.initialize(userId);
      // When a JARVIS notification is tapped, jump to the chat tab and
      // drain pending_messages → chat_history so the briefing/nudge body
      // is visible. Pre-fix the body would land in pending_messages but
      // the user, dropped on the board, never saw it (bug report:
      // "notification content vanishes, unable to see anywhere").
      _notificationService.setOnNotificationTap((_) {
        if (!mounted) return;
        _onItemTapped(0);
        ref.read(chatProvider.notifier).reloadPendingMessages();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(activeUserProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: false,
      extendBodyBehindAppBar: false,
      backgroundColor: JarvisTheme.background,
      body: Column(
        children: [
          // Custom top bar
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + JarvisTheme.sm,
              left: JarvisTheme.lg,
              right: JarvisTheme.lg,
              bottom: JarvisTheme.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onLongPress: () async {
                    // Test notification: instant + scheduled 2 min
                    await _notificationService.showTestNotification();
                    await _notificationService.scheduleTestNotification(minutesFromNow: 2);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Test: instant + 2 min scheduled notification sent'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  child: const JarvisLogo(fontSize: 20),
                ),
                if (user != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.settings_outlined,
                          color: JarvisTheme.textSecondary,
                          size: 22,
                        ),
                        tooltip: 'Settings',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(user: user),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      UserAvatar(
                        user: user,
                        size: 32,
                        showRing: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Main content area with swipe navigation
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _selectedIndex = index);
              },
              children: _screens,
            ),
          ),
        ],
      ),
      // Custom bottom navigation bar with long press support
      bottomNavigationBar: SafeArea(
        bottom: true,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: JarvisTheme.surface,
            border: Border(
              top: BorderSide(
                color: JarvisTheme.surface2,
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildChatNavItem(user),
              _buildBoardNavItem(user),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color accentColor,
  }) {
    final isActive = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(minHeight: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active indicator line
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: 24,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isActive ? accentColor : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                key: ValueKey(icon),
                size: 24,
                color: isActive ? accentColor : JarvisTheme.textMuted,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: isActive
                  ? Container(
                      key: const ValueKey('label'),
                      margin: const EdgeInsets.only(top: 2),
                      child: Text(
                        label,
                        style: JarvisTheme.bodySmall.copyWith(
                          color: accentColor,
                          fontSize: 10,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatNavItem(UserProfile? user) {
    final accentColor = user?.accentColor ?? JarvisTheme.pallavAccent;
    final isActive = _selectedIndex == 0;
    final chatIcon = _isRoseMode.value ? Icons.smart_toy : Icons.chat_bubble_outline;
    final chatLabel = _isRoseMode.value ? 'ROSE' : 'Chat';

    return GestureDetector(
      onTap: () => _onItemTapped(0),
      onLongPress: () {
        _isRoseMode.value = !_isRoseMode.value;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(minHeight: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active indicator line
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: 24,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isActive ? accentColor : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                chatIcon,
                key: ValueKey(chatIcon),
                size: 24,
                color: isActive ? accentColor : JarvisTheme.textMuted,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: isActive
                  ? Container(
                      key: const ValueKey('chat_label'),
                      margin: const EdgeInsets.only(top: 2),
                      child: Text(
                        chatLabel,
                        style: JarvisTheme.bodySmall.copyWith(
                          color: accentColor,
                          fontSize: 10,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('chat_empty')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardNavItem(UserProfile? user) {
    final accentColor = user?.accentColor ?? JarvisTheme.pallavAccent;
    final isActive = _selectedIndex == 1;

    // Get current section icon and name
    final sectionIcon = _getCurrentSectionIcon(user);
    final sectionName = _getCurrentSectionName(user);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onItemTapped(1),
      onLongPress: () {
        // Dismiss any keyboard first to prevent the long-press keyboard bug
        FocusScope.of(context).unfocus();
        _showBoardLongPressMenu(context, user, accentColor);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(minHeight: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active indicator line
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: 24,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isActive ? accentColor : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                sectionIcon,
                key: ValueKey(sectionIcon),
                size: 24,
                color: isActive ? accentColor : JarvisTheme.textMuted,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: isActive
                  ? Container(
                      key: ValueKey('board_$sectionName'),
                      margin: const EdgeInsets.only(top: 2),
                      child: Text(
                        sectionName,
                        style: JarvisTheme.bodySmall.copyWith(
                          color: accentColor,
                          fontSize: 10,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('board_empty')),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCurrentSectionIcon(UserProfile? user) {
    if (user == null) return Icons.dashboard_outlined;

    final sections = user.boardSections;
    final index = _boardSectionIndex.value.clamp(0, sections.length - 1);
    final section = sections[index];

    return _getSectionIconData(section);
  }

  String _getCurrentSectionName(UserProfile? user) {
    if (user == null) return 'Board';

    final sections = user.boardSections;
    final index = _boardSectionIndex.value.clamp(0, sections.length - 1);
    return sections[index];
  }

  IconData _getSectionIconData(String section) {
    switch (section) {
      case 'Tasks':
        return Icons.checklist;
      case 'Habits':
        return Icons.repeat;
      case 'Thoughts':
        return Icons.lightbulb_outline;
      case 'Finance':
        return Icons.account_balance_wallet_outlined;
      case 'Goals':
        return Icons.flag_outlined;
      case 'Meals':
        return Icons.restaurant_outlined;
      default:
        return Icons.dashboard_outlined;
    }
  }

  void _showBoardLongPressMenu(BuildContext context, UserProfile? user, Color accentColor) {
    if (user == null) return;

    final sections = user.boardSections;
    final currentIndex = _boardSectionIndex.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        duration: const Duration(milliseconds: 250),
        vsync: this,
      ),
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisTheme.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Jump to Section',
                  style: JarvisTheme.bodyLarge.copyWith(
                    color: JarvisTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...sections.asMap().entries.map((entry) {
                final sectionIndex = entry.key;
                final section = entry.value;
                final isCurrentSection = sectionIndex == currentIndex;
                return ListTile(
                  leading: _getSectionIcon(section),
                  title: Text(
                    section,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: isCurrentSection ? accentColor : JarvisTheme.textPrimary,
                      fontWeight: isCurrentSection ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: isCurrentSection
                      ? Icon(Icons.circle, size: 8, color: accentColor)
                      : null,
                  tileColor: isCurrentSection ? accentColor.withOpacity(0.08) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(context);
                    _boardSectionIndex.value = sectionIndex;
                    _onItemTapped(1);
                  },
                );
              }).toList(),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Icon _getSectionIcon(String section) {
    switch (section) {
      case 'Tasks':
        return const Icon(Icons.checklist, color: Colors.blue);
      case 'Habits':
        return const Icon(Icons.repeat, color: Colors.green);
      case 'Thoughts':
        return const Icon(Icons.lightbulb_outline, color: Colors.orange);
      case 'Finance':
        return const Icon(Icons.account_balance_wallet_outlined, color: Colors.purple);
      case 'Goals':
        return const Icon(Icons.flag_outlined, color: Colors.red);
      case 'Meals':
        return const Icon(Icons.restaurant_outlined, color: Colors.teal);
      default:
        return const Icon(Icons.dashboard_outlined, color: Colors.grey);
    }
  }
}
