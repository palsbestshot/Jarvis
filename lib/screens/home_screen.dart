import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/jarvis_logo.dart';
import '../widgets/user_avatar.dart';
import '../providers/auth_provider.dart';
import '../providers/widget_action_provider.dart';
import '../providers/notification_action_provider.dart';
import '../providers/notification_service_provider.dart';
import '../providers/app_lifecycle_provider.dart';
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
    // Instantiate through the provider so chat_provider and any other
    // code that needs a ref to NotificationService gets the same instance.
    _notificationService = ref.read(notificationServiceProvider);
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
    // Mirror the lifecycle into a provider so chat_provider can check
    // whether we're backgrounded without needing its own observer.
    ref.read(appLifecycleProvider.notifier).state = state;

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

  /// Debug affordance: long-press the JARVIS wordmark to fire a test
  /// notification. Android uses flutter_local_notifications directly
  /// (instant + 2 min scheduled). Web hits the sendTestPush Cloud
  /// Function, which reads the user's device_tokens/web doc and
  /// bounces a real FCM push — the round-trip Rakhi actually needs to
  /// verify from her phone.
  Future<void> _onLogoLongPress(UserProfile? user) async {
    if (kIsWeb) {
      if (user == null) return;
      try {
        final resp = await http.post(
          Uri.parse(AppConstants.testPushUrl),
          headers: {
            'content-type': 'application/json',
            'x-ingest-secret': AppConstants.ingestSecret,
          },
          body: jsonEncode({'userId': user.id}),
        );
        String label;
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          final sent = json['sent_to'] as Map<String, dynamic>? ?? {};
          // sendTestPush now returns a rich per-channel shape
          // {exists, has_token, delivered, error, message_id}.
          final web = sent['web'] as Map<String, dynamic>?;
          final primary = sent['primary'] as Map<String, dynamic>?;
          final webDelivered = web?['delivered'] == true;
          final primaryDelivered = primary?['delivered'] == true;
          final webError = web?['error']?.toString();
          if (webDelivered || primaryDelivered) {
            label = 'Test push delivered '
                '(${webDelivered ? 'web' : ''}'
                '${webDelivered && primaryDelivered ? ' + ' : ''}'
                '${primaryDelivered ? 'android' : ''}).';
          } else if (webError != null && webError.isNotEmpty) {
            label = 'Web push failed: $webError';
          } else {
            label =
                'No device tokens registered yet. Grant notification '
                'permission first by opening chat.';
          }
        } else {
          label = 'Test push failed: ${resp.statusCode}';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(label),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Test push error: $e'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
      return;
    }

    // Android: keep the existing instant + 2-min scheduled test.
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
    // NotificationService is disposed by its provider (ref.onDispose),
    // so we must NOT dispose it here — doing so double-cancels the
    // internal subscriptions.
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(activeUserProvider);

    // React to a notification tap by switching to the chat tab. Per product
    // decision every notification (task reminder, chat reply, briefing)
    // lands on Jarvis chat, so we don't branch on the action value yet.
    ref.listen<String?>(notificationActionProvider, (prev, next) {
      if (next == null) return;
      _onItemTapped(0);
      // Clear so a second identical tap still fires the listener.
      Future.microtask(() {
        if (!mounted) return;
        ref.read(notificationActionProvider.notifier).state = null;
      });
    });

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
                  onLongPress: () => _onLogoLongPress(user),
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
      barrierColor: const Color(0x66000000),
      transitionAnimationController: AnimationController(
        duration: const Duration(milliseconds: 220),
        vsync: this,
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 72),
          child: Container(
            decoration: BoxDecoration(
              color: JarvisTheme.surface2,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Jump to section',
                              style: TextStyle(
                                fontFamily: 'InstrumentSerif',
                                fontSize: 18,
                                color: JarvisTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Long press any tab to switch',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 11,
                                color: JarvisTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ...sections.asMap().entries.map((entry) {
                  final sectionIndex = entry.key;
                  final section = entry.value;
                  final isActive = sectionIndex == currentIndex;
                  return _buildSectionMenuRow(
                    name: section,
                    subtitle: _sectionSubtitle(section),
                    icon: _getSectionIconData(section),
                    accent: accentColor,
                    isActive: isActive,
                    onTap: () {
                      Navigator.pop(ctx);
                      _boardSectionIndex.value = sectionIndex;
                      _onItemTapped(1);
                    },
                  );
                }),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionMenuRow({
    required String name,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? accent.withOpacity(0.14) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive ? accent : JarvisTheme.surface3,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: isActive
                    ? const Color(0xFF2A1C0A)
                    : JarvisTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? accent : JarvisTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: JarvisTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _sectionSubtitle(String section) {
    switch (section) {
      case 'Tasks':
        return 'Today\'s checklist';
      case 'Time':
        return 'Daily visits & hours';
      case 'Habits':
        return 'Daily streaks';
      case 'Thoughts':
        return 'Captured notes';
      case 'Finance':
        return 'Net worth · entries';
      case 'Goals':
        return 'Roadmap progress';
      case 'Meals':
        return 'Plans & dishes';
      default:
        return '';
    }
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
