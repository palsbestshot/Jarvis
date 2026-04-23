import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/agent_provider.dart';
import '../../providers/widget_action_provider.dart';
import '../../services/audio_service.dart';
import '../../services/firestore_service.dart';
import '../../models/chat_message.dart';
import '../../models/agent_response.dart';
import '../../models/user_profile.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final ValueNotifier<bool>? isRoseModeNotifier;
  // Widget deep-link handling moved to widgetActionProvider (Riverpod
  // StateProvider) — ChatScreen watches it in build() and reacts whenever
  // a 'chat' or 'voice' action is set by HomeScreen. The old pattern
  // (ValueNotifier<int> signals passed down the tree) was fragile because
  // the bump could happen before ChatScreen was listening.
  const ChatScreen({
    super.key,
    this.isRoseModeNotifier,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

enum ChatMode { chat, agent }

class _ChatScreenState extends ConsumerState<ChatScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  
  // Chat mode state
  ChatMode _currentMode = ChatMode.chat;
  
  // Typing animation
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;
  
  // Voice recording state
  bool _isRecording = false;
  String _recordingDuration = '0:00';
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  
  // Waveform animation controllers (5 bars)
  late List<AnimationController> _waveformControllers;
  late List<Animation<double>> _waveformAnimations;

  // Rotating placeholder hints
  static const List<String> _placeholderHints = [
    'Add a task...',
    'Set a reminder...',
    'Log an expense...',
    'Save a thought...',
    'Ask me anything...',
    'Track a habit...',
  ];
  int _currentHintIndex = 0;
  Timer? _hintRotationTimer;

  // Track task states for visual feedback in chat
  final Map<String, String> _taskStates = {}; // taskId -> 'done' | 'postponed'

  @override
  void initState() {
    super.initState();
    
    // Initialize typing animation
    _typingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _typingAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _typingAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Initialize waveform animations (5 bars)
    _waveformControllers = List.generate(5, (index) {
      final duration = Duration(milliseconds: 300 + (index * 75));
      return AnimationController(
        duration: duration,
        vsync: this,
      )..repeat(reverse: true);
    });
    
    _waveformAnimations = _waveformControllers.map((controller) {
      return Tween<double>(begin: 4.0, end: 20.0).animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ),
      );
    }).toList();
    
    // Start rotating placeholder hints
    _hintRotationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {
          _currentHintIndex = (_currentHintIndex + 1) % _placeholderHints.length;
        });
      }
    });

    // Listen to rose mode changes from home screen
    widget.isRoseModeNotifier?.addListener(_onRoseModeChanged);

    // Catch any widget action that was set before this ChatScreen was
    // built (cold-start race). ref.listen only fires on changes after
    // registration, so we need to check the current value too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(widgetActionProvider);
      if (pending != null) {
        ref.read(widgetActionProvider.notifier).state = null;
        if (pending == 'chat') _onFocusInputRequested();
        if (pending == 'voice') _onStartVoiceRequested();
      }
    });

    // Initialize audio recorder
    print('DEBUG: initRecorder called');
    _initAudioRecorder();
  }

  void _onRoseModeChanged() {
    setState(() {
      _currentMode = (widget.isRoseModeNotifier?.value ?? false)
          ? ChatMode.agent
          : ChatMode.chat;
    });
  }

  // Pop up the keyboard and focus the text field. Called when the user
  // tapped the chat bar on the home widget.
  //
  // A 200ms delay gives Android's transition animation time to finish;
  // requesting focus mid-transition can result in the keyboard opening
  // then immediately dismissing. After requestFocus we also explicitly
  // call TextInput.show because on Android 13+ soft-keyboard auto-show
  // on focus is inconsistent across OEMs (Samsung OneUI sometimes
  // swallows the automatic show).
  void _onFocusInputRequested() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      // Request focus directly on the node (not via FocusScope) so it
      // doesn't get captured by some other focus group.
      _inputFocusNode.requestFocus();
      // Explicitly show the soft keyboard.
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  // Start voice recording. Called when the user tapped the mic icon on
  // the home widget.
  void _onStartVoiceRequested() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (!_isRecording) _startRecording();
    });
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _initAudioRecorder() async {
    try {
      final audioService = ref.read(audioServiceProvider);
      await audioService.initRecorder();
    } catch (e) {
      // Silently fail - user will see error when trying to record
    }
  }

  @override
  void dispose() {
    widget.isRoseModeNotifier?.removeListener(_onRoseModeChanged);
    _inputFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    
    // Dispose waveform controllers
    for (final controller in _waveformControllers) {
      controller.dispose();
    }
    
    // Cancel timers
    _recordingTimer?.cancel();
    _hintRotationTimer?.cancel();
    
    // Dispose audio services
    final audioService = ref.read(audioServiceProvider);
    audioService.disposeRecorder();
    audioService.disposePlayer();
    
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_currentMode == ChatMode.chat) {
      ref.read(chatProvider.notifier).sendMessage(text, 'text');
    } else {
      final user = ref.read(activeUserProvider);
      if (user != null) {
        ref.read(agentNotifierProvider(user).notifier).sendMessage(text);
      }
    }
    
    _textController.clear();
    _scrollToBottom();
  }

  void _startRecording() async {
    print('DEBUG: _startRecording called');
    try {
      final audioService = ref.read(audioServiceProvider);
      await audioService.startRecording();
      
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
        _recordingDuration = '0:00';
      });
      
      // Start timer for recording duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingSeconds++;
          final minutes = _recordingSeconds ~/ 60;
          final seconds = _recordingSeconds % 60;
          _recordingDuration = '$minutes:${seconds.toString().padLeft(2, '0')}';
        });
      });
      
      // Start waveform animations
      for (final controller in _waveformControllers) {
        controller.repeat(reverse: true);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to start recording: ${e.toString()}');
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    
    try {
      final audioService = ref.read(audioServiceProvider);
      await audioService.stopRecording();
    } catch (e) {
      // Ignore errors during cancellation
    }
    
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _recordingDuration = '0:00';
    });
    
    // Stop waveform animations
    for (final controller in _waveformControllers) {
      controller.stop();
    }
  }

  Future<void> _sendVoiceMessage() async {
    _recordingTimer?.cancel();
    final audioService = ref.read(audioServiceProvider);
    final filePath = await audioService.stopRecording();
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _recordingDuration = '0:00';
    });
    // Stop waveform animations
    for (final controller in _waveformControllers) {
      controller.stop();
    }
    if (filePath != null && filePath.isNotEmpty) {
      print('DEBUG: Sending voice file: $filePath');
      await ref.read(chatProvider.notifier)
        .sendVoiceMessage(filePath);
      _scrollToBottom();
    } else {
      print('DEBUG: filePath is null or empty, not sending');
    }
  }

  void _showErrorSnackBar(String message) {
    // Explicit textPrimary colour so the message doesn't inherit a
    // black foreground from the default Material theme (was rendering
    // black-on-black surface2 and being unreadable).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: JarvisTheme.textPrimary),
        ),
        backgroundColor: JarvisTheme.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JarvisTheme.medium),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, UserProfile user) {
    // Check if this is a task list message
    if (message.isTaskList) {
      return _buildTaskListBubble(message.content, user);
    }
    // Morning / evening briefing — structured JSON produced by Cloud
    // Functions morningBriefing / eveningWrap. Render as a rich card
    // instead of dumping raw JSON.
    if (message.messageType == 'morning_briefing' ||
        message.messageType == 'evening_wrap') {
      final parsed = _tryParseBriefing(message.content);
      if (parsed != null) {
        return _buildBriefingCard(parsed, message, user);
      }
    }

    final accentColor = user.accentColor;
    final isUser = message.isUser;
    final isToolResult = message.isToolResult;
    final isVoiceMessage = message.inputType == 'voice' && isUser;

    // Timestamp
    final time = DateFormat('h:mm a').format(message.timestamp);

    // Bubble styling
    Color backgroundColor;
    Color borderColor;
    BorderRadius borderRadius;
    Alignment alignment;

    if (isUser) {
      backgroundColor = JarvisTheme.surface2;
      borderColor = accentColor.withOpacity(0.2);
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(4),
      );
      alignment = Alignment.centerRight;
    } else if (isToolResult) {
      backgroundColor = JarvisTheme.surface;
      borderColor = Colors.transparent;
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      );
      alignment = Alignment.centerLeft;
    } else {
      backgroundColor = JarvisTheme.surface;
      borderColor = Colors.transparent;
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      );
      alignment = Alignment.centerLeft;
    }

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(
          vertical: JarvisTheme.xs,
          horizontal: JarvisTheme.md,
        ),
        padding: const EdgeInsets.all(JarvisTheme.md),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
          borderRadius: borderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isVoiceMessage)
              Row(
                children: [
                  Icon(
                    Icons.mic,
                    color: accentColor,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      message.content,
                      style: JarvisTheme.bodyMedium.copyWith(
                        color: JarvisTheme.textPrimary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                message.content,
                style: isToolResult
                    ? JarvisTheme.bodySmall.copyWith(color: JarvisTheme.confirmText)
                    : JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary),
              ),
            const SizedBox(height: JarvisTheme.xs),
            Text(
              time,
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Briefing JSON → structured map, or null if it isn't valid JSON.
  Map<String, dynamic>? _tryParseBriefing(String raw) {
    try {
      final trimmed = raw.trim();
      if (!trimmed.startsWith('{')) return null;
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  // Morning + evening briefing card. Shows quote, insight/reflection,
  // focus task, and top tasks list. Morning and evening share this
  // renderer — fields differ slightly (morning: insight + focus_one_thing;
  // evening: reflection + tomorrow_focus + tomorrow_first_task).
  Widget _buildBriefingCard(
    Map<String, dynamic> data,
    ChatMessage message,
    UserProfile user,
  ) {
    final accent = user.accentColor;
    final isEvening = data['type'] == 'evening_wrap';
    final greeting = (data['greeting'] ?? '').toString();
    final quote = (data['quote'] ?? '').toString();
    final insight = (data['insight'] ?? data['reflection'] ?? '').toString();
    final subInsight = (data['tomorrow_focus'] ?? '').toString();
    final focusTask =
        (data['focus_one_thing'] ?? data['tomorrow_first_task'] ?? '')
            .toString();
    final completedTasks = (data['completedTasks'] ?? 0) as int;
    final totalTasks = (data['totalTasks'] ?? 0) as int;
    final rolledOver = (data['rolledOverCount'] ?? 0) as int;

    // Pull tasks — morning uses topTasks (list of titles);
    // evening uses pendingTasks + tomorrowTasks (list of maps).
    final topTasks = <String>[];
    final rawTop = data['topTasks'];
    if (rawTop is List) {
      for (final t in rawTop) {
        topTasks.add(t.toString());
      }
    }
    final tomorrowTitles = <String>[];
    final rawTomorrow = data['tomorrowTasks'];
    if (rawTomorrow is List) {
      for (final t in rawTomorrow) {
        if (t is Map) tomorrowTitles.add((t['title'] ?? '').toString());
      }
    }
    final timeStr = DateFormat('h:mm a').format(message.timestamp);

    return Padding(
      padding: EdgeInsets.only(left: 0, right: 80, top: 6, bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: JarvisTheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
          border: Border.all(color: accent.withOpacity(0.35), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEvening ? Icons.nightlight_round : Icons.wb_sunny,
                  color: accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  greeting.isNotEmpty
                      ? greeting
                      : (isEvening ? 'Evening wrap' : 'Good morning'),
                  style: JarvisTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const Spacer(),
                if (isEvening)
                  Text(
                    '$completedTasks / $totalTasks done',
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textMuted),
                  )
                else if (totalTasks > 0)
                  Text(
                    '$totalTasks due'
                    '${rolledOver > 0 ? ' · $rolledOver rolled over' : ''}',
                    style: JarvisTheme.bodySmall
                        .copyWith(color: JarvisTheme.textMuted),
                  ),
              ],
            ),
            if (quote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(color: accent, width: 3),
                  ),
                ),
                child: Text(
                  quote,
                  style: JarvisTheme.bodyMedium.copyWith(
                    fontStyle: FontStyle.italic,
                    color: JarvisTheme.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (insight.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                isEvening ? 'Today' : 'Plan',
                style: JarvisTheme.labelMedium
                    .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                insight,
                style: JarvisTheme.bodyMedium.copyWith(
                  color: JarvisTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
            if (subInsight.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Tomorrow',
                style: JarvisTheme.labelMedium
                    .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                subInsight,
                style: JarvisTheme.bodyMedium.copyWith(
                  color: JarvisTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ],
            if (focusTask.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isEvening ? Icons.wb_twilight : Icons.flag,
                      color: accent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEvening ? 'Start tomorrow with' : 'Crack this first',
                            style: JarvisTheme.bodySmall.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            focusTask,
                            style: JarvisTheme.bodyMedium.copyWith(
                              color: JarvisTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Task list (morning: topTasks; evening: tomorrowTitles if any)
            if (!isEvening && topTasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                "Today's lineup",
                style: JarvisTheme.labelMedium
                    .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 4),
              for (final t in topTasks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.radio_button_unchecked,
                          size: 12, color: JarvisTheme.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t,
                          style: JarvisTheme.bodySmall
                              .copyWith(color: JarvisTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (isEvening && tomorrowTitles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                "Tomorrow's lineup",
                style: JarvisTheme.labelMedium
                    .copyWith(color: JarvisTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 4),
              for (final t in tomorrowTitles.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.radio_button_unchecked,
                          size: 12, color: JarvisTheme.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t,
                          style: JarvisTheme.bodySmall
                              .copyWith(color: JarvisTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              timeStr,
              style: JarvisTheme.bodySmall
                  .copyWith(color: JarvisTheme.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskListBubble(String content, UserProfile user) {
    // Parse the task list content
    final lines = content.split('\n');
    final taskLines = <String>[];
    bool inTaskList = false;
    
    for (final line in lines) {
      if (line == 'TASK_LIST_START') {
        inTaskList = true;
        continue;
      }
      if (line == 'TASK_LIST_END') {
        break;
      }
      if (inTaskList && line.isNotEmpty) {
        taskLines.add(line);
      }
    }
    
    final tasks = <Map<String, String>>[];
    for (final line in taskLines) {
      final parts = line.split('|');
      if (parts.length >= 4) {
        tasks.add({
          'id': parts[0],
          'title': parts[1],
          'due_date': parts[2],
          'priority': parts[3],
        });
      }
    }
    
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(
          vertical: JarvisTheme.xs,
          horizontal: JarvisTheme.md,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JarvisTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: JarvisTheme.surface2,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Your Tasks (${tasks.length} pending)',
              style: JarvisTheme.labelMedium.copyWith(
                color: JarvisTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            
            // Task list
            ...tasks.map((task) {
              final taskId = task['id']!;
              final taskState = _taskStates[taskId];
              final isDone = taskState == 'done';
              final isPostponed = taskState == 'postponed';

              return Column(
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isPostponed ? 0.45 : 1.0,
                    child: Row(
                      children: [
                        // Task title
                        Expanded(
                          child: Text(
                            task['title']!,
                            style: JarvisTheme.bodyMedium.copyWith(
                              color: isDone
                                  ? JarvisTheme.textMuted
                                  : JarvisTheme.textPrimary,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),

                        // Action buttons (hidden once acted on)
                        if (taskState == null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Check button
                              Tooltip(
                                message: 'Mark as done',
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: IconButton(
                                    onPressed: () => _markTaskDone(taskId, user),
                                    icon: Icon(
                                      Icons.check_circle_outline,
                                      color: user.accentColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),

                              // Postpone button
                              Tooltip(
                                message: 'Postpone to tomorrow',
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: IconButton(
                                    onPressed: () => _postponeTask(taskId, user),
                                    icon: Icon(
                                      Icons.skip_next,
                                      color: user.accentColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              isDone ? 'Done' : 'Moved',
                              style: JarvisTheme.bodySmall.copyWith(
                                color: JarvisTheme.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Divider between tasks (except last)
                  if (task != tasks.last)
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      color: JarvisTheme.surface2,
                    ),
                ],
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Future<void> _markTaskDone(String taskId, UserProfile user) async {
    try {
      final firestoreService = FirestoreService();
      await firestoreService.markTaskDone(user.id, taskId);

      setState(() => _taskStates[taskId] = 'done');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u2713 Task completed',
            style: TextStyle(color: JarvisTheme.confirmText),
          ),
          backgroundColor: JarvisTheme.surface2,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark task as done: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _postponeTask(String taskId, UserProfile user) async {
    try {
      final firestoreService = FirestoreService();

      // Calculate tomorrow's date
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      await firestoreService.updateTask(user.id, taskId, {
        'due_date': tomorrowStr,
        'status': 'pending',
        'updated_at': FieldValue.serverTimestamp(),
      });

      setState(() => _taskStates[taskId] = 'postponed');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u2713 Postponed to tomorrow',
            style: TextStyle(color: JarvisTheme.confirmText),
          ),
          backgroundColor: JarvisTheme.surface2,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to postpone task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildAgentMessageBubble(AgentChatMessage message, UserProfile user) {
    final accentColor = user.accentColor;
    final isUser = message.role == 'user';
    final time = DateFormat('h:mm a').format(message.timestamp);

    // Bubble styling
    Color backgroundColor;
    Color borderColor;
    BorderRadius borderRadius;
    Alignment alignment;

    if (isUser) {
      backgroundColor = JarvisTheme.surface2;
      borderColor = accentColor.withOpacity(0.2);
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(4),
      );
      alignment = Alignment.centerRight;
    } else {
      backgroundColor = JarvisTheme.surface;
      borderColor = Colors.transparent;
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      );
      alignment = Alignment.centerLeft;
    }

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(
          vertical: JarvisTheme.xs,
          horizontal: JarvisTheme.md,
        ),
        padding: const EdgeInsets.all(JarvisTheme.md),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
          borderRadius: borderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: JarvisTheme.bodyMedium.copyWith(
                color: JarvisTheme.textPrimary,
              ),
            ),
            const SizedBox(height: JarvisTheme.xs),
            Text(
              time,
              style: JarvisTheme.bodySmall.copyWith(
                color: JarvisTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(UserProfile user) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(
          vertical: JarvisTheme.xs,
          horizontal: JarvisTheme.md,
        ),
        padding: const EdgeInsets.all(JarvisTheme.md),
        decoration: BoxDecoration(
          color: JarvisTheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _typingAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _typingAnimation.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: user.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _typingAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _typingAnimation.value * 0.7,
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: user.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _typingAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _typingAnimation.value * 0.4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: user.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformAnimation(UserProfile user) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return AnimatedBuilder(
          animation: _waveformAnimations[index],
          builder: (context, child) {
            return Container(
              width: 4,
              height: _waveformAnimations[index].value,
              margin: EdgeInsets.only(
                left: index == 0 ? 0 : 2,
                right: index == 4 ? 0 : 2,
              ),
              decoration: BoxDecoration(
                color: user.accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildRecordingInputBar(UserProfile user) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          left: JarvisTheme.md,
          right: JarvisTheme.md,
          bottom: JarvisTheme.sm,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom > 0 
              ? 0 
              : MediaQuery.of(context).padding.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: JarvisTheme.md,
              vertical: JarvisTheme.sm,
            ),
            decoration: BoxDecoration(
              color: JarvisTheme.surface2,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: user.accentColor,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Cancel button (left)
                IconButton(
                  onPressed: _cancelRecording,
                  icon: Icon(
                    Icons.close,
                    color: JarvisTheme.textMuted,
                    size: 24,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                
                const SizedBox(width: JarvisTheme.sm),
                
                // Waveform animation (center)
                Expanded(
                  child: Center(
                    child: _buildWaveformAnimation(user),
                  ),
                ),
                
                const SizedBox(width: JarvisTheme.sm),
                
                // Duration + Send button (right side)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _recordingDuration,
                      style: JarvisTheme.bodySmall.copyWith(
                        color: JarvisTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    // Send button
                    IconButton(
                      onPressed: _sendVoiceMessage,
                      icon: Icon(
                        Icons.send,
                        color: user.accentColor,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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

  Widget _buildNormalInputBar(UserProfile user) {
    final hasText = _textController.text.isNotEmpty;
    final hintText = _currentMode == ChatMode.agent
        ? 'Ask ROSE to do something...'
        : _placeholderHints[_currentHintIndex];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          left: JarvisTheme.md,
          right: JarvisTheme.md,
          bottom: JarvisTheme.sm,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom > 0
                ? 0
                : MediaQuery.of(context).padding.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: JarvisTheme.md,
              vertical: JarvisTheme.sm,
            ),
            decoration: BoxDecoration(
              color: JarvisTheme.surface2,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: JarvisTheme.surface2,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Text field
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocusNode,
                    style: JarvisTheme.bodyMedium.copyWith(
                      color: JarvisTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: JarvisTheme.bodyMedium.copyWith(
                        color: JarvisTheme.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: 4,
                    minLines: 1,
                    onChanged: (value) {
                      setState(() {});
                    },
                    onSubmitted: (value) {
                      _sendMessage();
                    },
                  ),
                ),
                const SizedBox(width: JarvisTheme.sm),

                // Send button with scale animation (only when typing)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: child,
                  ),
                  child: hasText
                      ? SizedBox(
                          key: const ValueKey('send'),
                          width: 48,
                          height: 48,
                          child: IconButton(
                            onPressed: _sendMessage,
                            icon: Icon(
                              Icons.send,
                              color: user.accentColor,
                              size: 24,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('no_send')),
                ),

                // Camera button (chat mode only)
                if (_currentMode == ChatMode.chat)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      onPressed: _pickImage,
                      icon: Icon(
                        Icons.camera_alt_outlined,
                        color: user.accentColor,
                        size: 24,
                      ),
                    ),
                  ),

                // Mic button — hidden on web until the Whisper proxy is
                // wired (Phase 5). Browser voice capture needs MediaRecorder
                // + POST to the aiTranscribe Function, not flutter_sound's
                // file-based recording which has no temp dir in the browser.
                if (!kIsWeb)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      onPressed: _isRecording ? null : _startRecording,
                      icon: Icon(
                        Icons.mic,
                        color: user.accentColor,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: JarvisTheme.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: JarvisTheme.textPrimary),
              title: Text('Camera', style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: JarvisTheme.textPrimary),
              title: Text('Gallery', style: JarvisTheme.bodyMedium.copyWith(color: JarvisTheme.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    if (image != null) {
      await ref.read(chatProvider.notifier).sendImageMessage(image.path);
      _scrollToBottom();
    }
  }

  Widget _buildModeSwitcher(UserProfile user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Chat mode pill
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _currentMode = ChatMode.chat;
              });
              widget.isRoseModeNotifier?.value = false;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _currentMode == ChatMode.chat
                      ? user.accentColor
                      : JarvisTheme.surface2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Chat',
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: _currentMode == ChatMode.chat
                        ? Colors.white
                        : JarvisTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ROSE mode pill
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _currentMode = ChatMode.agent;
              });
              widget.isRoseModeNotifier?.value = true;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _currentMode == ChatMode.agent
                      ? user.accentColor
                      : JarvisTheme.surface2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'ROSE',
                  style: JarvisTheme.bodyMedium.copyWith(
                    color: _currentMode == ChatMode.agent
                        ? Colors.white
                        : JarvisTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentModeBanner(UserProfile user) {
    if (_currentMode != ChatMode.agent) return const SizedBox();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: user.accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: user.accentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            color: user.accentColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'ROSE mode — GPT-4o with web search',
            style: JarvisTheme.bodySmall.copyWith(
              color: user.accentColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    // React to widget deep-link actions. ref.listen fires only when the
    // value changes, not on every build. We consume the action (reset
    // to null) inside the handler so it can't be re-triggered on the
    // next rebuild.
    ref.listen<String?>(widgetActionProvider, (prev, next) {
      if (next == null) return;
      // Consume immediately so a second rebuild doesn't re-fire.
      Future.microtask(() {
        if (mounted) ref.read(widgetActionProvider.notifier).state = null;
      });
      if (next == 'chat') {
        _onFocusInputRequested();
      } else if (next == 'voice') {
        _onStartVoiceRequested();
      }
    });

    final user = ref.watch(activeUserProvider);
    final chatState = ref.watch(chatProvider);
    final agentState = user != null ? ref.watch(agentNotifierProvider(user)) : null;

    if (user == null) {
      return Scaffold(
        backgroundColor: JarvisTheme.background,
        body: const Center(
          child: Text('Please login first'),
        ),
      );
    }

    final bool isRoseMode = _currentMode == ChatMode.agent;
    
    // Get messages as dynamic list - no casting
    final List<dynamic> displayMessages = isRoseMode
      ? (agentState?.messages ?? [])
      : chatState.messages;
    
    final isLoading = isRoseMode
      ? agentState?.isLoading ?? false
      : chatState.isLoading;

    return Scaffold(
      backgroundColor: JarvisTheme.background,
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Mode switcher (only shown when not driven by home nav notifier)
            if (widget.isRoseModeNotifier == null)
              _buildModeSwitcher(user),

            // Agent mode banner
            _buildAgentModeBanner(user),
            
            // Messages list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.only(
                  top: 8,
                  bottom: 8,
                ),
                itemCount: displayMessages.length + (isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0 && isLoading) {
                    return _buildTypingIndicator(user);
                  }
                  
                  final messageIndex = isLoading ? index - 1 : index;
                  final dynamic message = displayMessages[messageIndex];
                  
                  Widget bubble;
                  if (message is ChatMessage) {
                    bubble = _buildMessageBubble(message, user);
                  } else if (message is AgentChatMessage) {
                    bubble = _buildAgentMessageBubble(message, user);
                  } else {
                    return const SizedBox.shrink();
                  }
                  // Slide-in animation for newest message (index 0 or 1 when loading)
                  final isNewest = messageIndex == 0;
                  if (isNewest) {
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(message is ChatMessage ? message.id : (message as AgentChatMessage).id),
                      tween: Tween(begin: 24.0, end: 0.0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      builder: (context, offset, child) => Transform.translate(
                        offset: Offset(0, offset),
                        child: Opacity(opacity: 1 - (offset / 24).clamp(0.0, 1.0), child: child),
                      ),
                      child: bubble,
                    );
                  }
                  return bubble;
                },
              ),
            ),
            
            // Input bar
            if (_isRecording)
              _buildRecordingInputBar(user)
            else
              _buildNormalInputBar(user),
          ],
        ),
      ),
    );
  }
}
