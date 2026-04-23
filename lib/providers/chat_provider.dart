import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/time_categories.dart';
import '../models/chat_message.dart';
import '../models/time_log.dart';
import '../services/firestore_service.dart';
import '../services/claude_service.dart';
import '../services/openai_service.dart';
import '../services/audio_service.dart';
import '../services/home_widget_service.dart';
import 'auth_provider.dart';

// Chat State
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  const ChatState({
    required this.messages,
    required this.isLoading,
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

// Chat Notifier
class ChatNotifier extends Notifier<ChatState> {
  late FirestoreService _firestoreService;
  late ClaudeService _claudeService;

  @override
  ChatState build() {
    _firestoreService = FirestoreService();
    _claudeService = ClaudeService();
    
    // Load initial messages from Firestore
    _loadInitialMessages();
    
    return const ChatState(
      messages: [],
      isLoading: false,
      error: null,
    );
  }

  Future<void> _loadInitialMessages() async {
    final userId = ref.read(activeUserIdProvider);
    if (userId == null) return;

    try {
      // Load pending messages first
      await _loadPendingMessages(userId);
      
      // Then load chat history
      final stream = _firestoreService.chatStream(userId);
      stream.listen((firestoreMessages) {
        final messages = firestoreMessages
            .map((data) => ChatMessage.fromFirestore(data, data['id']))
            .toList();
        state = state.copyWith(messages: messages);
      });
    } catch (e) {
      // Silently fail - app will work without initial messages
    }
  }

  Future<void> _loadPendingMessages(String userId) async {
    try {
      final pendingMessagesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('pending_messages')
          .where('fetched', isEqualTo: false)
          .orderBy('created_at', descending: false)
          .get();

      if (pendingMessagesSnapshot.docs.isEmpty) return;

      // Persist each pending message into chat_history so it survives
      // app restarts (pending_messages is ephemeral — the chatStream below
      // only listens to chat_history). Previously briefings showed briefly
      // then disappeared when chatStream ticked and overwrote state.
      final historyRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('chat_history');
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in pendingMessagesSnapshot.docs) {
        final data = doc.data();
        final createdAt = data['created_at'];
        final timestamp = createdAt is Timestamp
            ? createdAt
            : Timestamp.now();
        final historyDoc = historyRef.doc();
        batch.set(historyDoc, {
          'role': 'assistant',
          'content': data['content'] ?? '',
          'input_type': 'text',
          'timestamp': timestamp,
          'message_type': data['message_type'] ?? 'system',
          'source': 'pending_message',
          'source_doc_id': doc.id,
        });
        batch.update(doc.reference, {'fetched': true});
      }
      await batch.commit();
      // chatStream below will pick these up on its next tick.
    } catch (e) {
      print('Error loading pending messages: $e');
    }
  }

  Future<void> sendMessage(String text, String inputType) async {
    final userId = ref.read(activeUserIdProvider);
    final user = ref.read(activeUserProvider);
    
    if (userId == null || user == null) {
      state = state.copyWith(
        error: 'No user logged in',
        isLoading: false,
      );
      return;
    }

    // Add user message to local state
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text,
      inputType: inputType,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [userMessage, ...state.messages],
      isLoading: true,
      error: null,
    );

    try {
      // Get recent data for context
      final recentData = await _firestoreService.getRecentData(userId);
      final recentTasks = recentData['tasks'] as List<Map<String, dynamic>>;
      final recentThoughts = recentData['thoughts'] as List<Map<String, dynamic>>;
      final recentChats = await _firestoreService.getRecentChats(userId, limit: 10);

      // Call Claude API
      final response = await _claudeService.sendMessage(
        userId: userId,
        user: user,
        userMessage: text,
        inputType: inputType,
        recentTasks: recentTasks,
        recentThoughts: recentThoughts,
        recentChats: recentChats,
      );

      if (response.hasToolCall && response.toolName != null && response.toolInput != null) {
        // Execute tool. Pass the user's raw text so report_bug can store it
        // verbatim — Claude's tool input for bug text is unreliable (it
        // paraphrases/translates/cleans up no matter what the prompt says).
        final toolResult = await _executeTool(
          userId: userId,
          toolName: response.toolName!,
          toolInput: response.toolInput!,
          originalUserText: text,
        );

        // Add tool result message
        final toolMessage = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'tool_result',
          content: toolResult,
          inputType: 'text',
          timestamp: DateTime.now(),
          toolName: response.toolName,
          isTaskList: toolResult.contains('TASK_LIST_START'),
        );

        // Save both messages to Firestore (stream will update state.messages)
        await _firestoreService.saveChatMessage(userId, userMessage.toFirestore());
        await _firestoreService.saveChatMessage(userId, toolMessage.toFirestore());
        state = state.copyWith(isLoading: false);
      } else if (response.text != null) {
        // Add assistant message
        final assistantMessage = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: response.text!,
          inputType: 'text',
          timestamp: DateTime.now(),
        );

        // Save both messages to Firestore (stream will update state.messages)
        await _firestoreService.saveChatMessage(userId, userMessage.toFirestore());
        await _firestoreService.saveChatMessage(userId, assistantMessage.toFirestore());
        state = state.copyWith(isLoading: false);
      } else {
        throw Exception('No response from Claude');
      }
    } catch (e) {
      // Add error message
      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'assistant',
        content: 'Something went wrong. Try again.',
        inputType: 'text',
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [errorMessage, ...state.messages],
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> sendVoiceMessage(String filePath) async {
    print('DEBUG: sendVoiceMessage called with filePath: $filePath');
    final userId = ref.read(activeUserIdProvider);
    final user = ref.read(activeUserProvider);
    
    if (userId == null || user == null) {
      state = state.copyWith(
        error: 'No user logged in',
        isLoading: false,
      );
      return;
    }

    // Set loading state
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Get services from providers
      final openAIService = ref.read(openAIServiceProvider);
      final audioService = ref.read(audioServiceProvider);

      // 1. Transcribe audio using Whisper
      String transcript;
      try {
        transcript = await openAIService.transcribeAudio(filePath);
        print('DEBUG: Whisper transcript: $transcript');
      } catch (e) {
        print('DEBUG ERROR in sendVoiceMessage: $e');
        // Add error message to chat
        state = state.copyWith(
          messages: [
            ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              role: 'assistant',
              content: 'Voice failed: ${e.toString()}',
              inputType: 'text',
              timestamp: DateTime.now(),
            ),
            ...state.messages,
          ],
          isLoading: false,
        );
        return;
      }

      // 2. Add user voice message to local state
      final userMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'user',
        content: transcript,
        inputType: 'voice',
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [userMessage, ...state.messages],
      );

      // 3. Get recent data for context
      final recentData = await _firestoreService.getRecentData(userId);
      final recentTasks = recentData['tasks'] as List<Map<String, dynamic>>;
      final recentThoughts = recentData['thoughts'] as List<Map<String, dynamic>>;
      final recentChats = await _firestoreService.getRecentChats(userId, limit: 10);

      // 4. Call Claude API with voice input type
      final response = await _claudeService.sendMessage(
        userId: userId,
        user: user,
        userMessage: transcript,
        inputType: 'voice',
        recentTasks: recentTasks,
        recentThoughts: recentThoughts,
        recentChats: recentChats,
      );
      print('DEBUG: Claude response received');

      String assistantResponseText = '';

      if (response.hasToolCall && response.toolName != null && response.toolInput != null) {
        // Execute tool. Pass Whisper's transcript so report_bug stores the
        // verbatim spoken text — never Claude's cleaned-up rewrite.
        final toolResult = await _executeTool(
          userId: userId,
          toolName: response.toolName!,
          toolInput: response.toolInput!,
          originalUserText: transcript,
        );

        // Add tool result message
        final toolMessage = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'tool_result',
          content: toolResult,
          inputType: 'text',
          timestamp: DateTime.now(),
          toolName: response.toolName,
          isTaskList: toolResult.contains('TASK_LIST_START'),
        );

        // Save both messages to Firestore (stream will update state.messages)
        await _firestoreService.saveChatMessage(userId, userMessage.toFirestore());
        await _firestoreService.saveChatMessage(userId, toolMessage.toFirestore());

        assistantResponseText = toolResult;
      } else if (response.text != null) {
        // Save both messages to Firestore (stream will update state.messages)
        await _firestoreService.saveChatMessage(userId, userMessage.toFirestore());
        await _firestoreService.saveChatMessage(userId, ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: response.text!,
          inputType: 'text',
          timestamp: DateTime.now(),
        ).toFirestore());

        assistantResponseText = response.text!;
      } else {
        throw Exception('No response from Claude');
      }

      // 5. Generate TTS audio from assistant response
      if (assistantResponseText.isNotEmpty) {
        final audioBytes = await openAIService.generateSpeech(assistantResponseText, user.ttsVoice);
        
        // 6. Auto-play the TTS audio
        await audioService.playFromBytes(audioBytes);
      }

      // 7. Clear loading state
      state = state.copyWith(isLoading: false);

    } catch (e) {
      // Handle transcription errors with error message
      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'assistant',
        content: e.toString().contains('API key not configured')
            ? 'OpenAI API key not configured. Please set OPENAI_API_KEY environment variable.'
            : 'Voice message failed. Try typing instead.',
        inputType: 'text',
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [errorMessage, ...state.messages],
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<String> _executeTool({
    required String userId,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? originalUserText,
  }) async {
    final result = await _executeToolImpl(
      userId: userId,
      toolName: toolName,
      toolInput: toolInput,
      originalUserText: originalUserText,
    );
    // Flash successful action results on the home-screen widget so the user
    // sees confirmation even if the app is backgrounded. Only fire for tool
    // results that represent an action ("✓ …") — skip list/query returns
    // like show_board / query_emails since those aren't one-line messages
    // and don't fit the 90-char widget bar. Fire-and-forget; never throws.
    if (result.startsWith('✓')) {
      // Strip the leading checkmark + space for the widget display — the
      // widget bar is short and the checkmark is visual noise there.
      final widgetMsg = result.replaceFirst(RegExp(r'^✓\s*'), '');
      // ignore: unawaited_futures
      HomeWidgetService.showFeedback(widgetMsg);
    }
    return result;
  }

  Future<String> _executeToolImpl({
    required String userId,
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? originalUserText,
  }) async {
    switch (toolName) {
      case 'create_task':
        final taskId = await _firestoreService.createTask(userId, toolInput);
        final title = toolInput['title'] ?? 'task';
        final dueDate = toolInput['due_date'] != null ? 'due ${toolInput['due_date']}' : 'no date';
        return '✓ Added — $title, $dueDate';

      case 'create_recurring_task':
        final taskId = await _firestoreService.createRecurringTask(userId, toolInput);
        final title = toolInput['title'] ?? 'task';
        final frequency = toolInput['frequency'] ?? 'regularly';
        return '✓ Set up recurring — $title, $frequency';

      case 'update_task':
        final taskId = toolInput['task_id'] as String;
        final fields = toolInput['fields'] as Map<String, dynamic>;
        await _firestoreService.updateTask(userId, taskId, fields);
        return '✓ Updated — $taskId';

      case 'delete_task':
        final taskId = toolInput['task_id'] as String;
        await _firestoreService.deleteTask(userId, taskId);
        return '✓ Deleted task.';

      case 'mark_task_done':
        final taskId = toolInput['task_id'] as String;
        await _firestoreService.markTaskDone(userId, taskId);
        return '✓ Done — marked complete.';

      case 'save_thought':
        final thoughtId = await _firestoreService.saveThought(userId, toolInput);
        final title = toolInput['title'] ?? 'thought';
        return '✓ Saved — $title';

      case 'save_finance':
        final financeId = await _firestoreService.saveFinance(userId, toolInput);
        final title = toolInput['title'] ?? 'finance entry';
        return '✓ Finance saved — $title';

      case 'save_meal':
        final mealId = await _firestoreService.saveMeal(userId, toolInput);
        final dayOfWeek = toolInput['day_of_week'] ?? 'day';
        final mealType = toolInput['meal_type'] ?? 'meal';
        return '✓ Meal saved — $dayOfWeek $mealType';

      case 'save_goal':
        final goalId = await _firestoreService.saveGoal(userId, toolInput);
        final title = toolInput['title'] ?? 'goal';
        return '✓ Goal added — $title';

      case 'set_reminder':
        final reminderId = await _firestoreService.setReminder(userId, toolInput);
        final message = toolInput['message'] ?? 'reminder';
        return '✓ Reminder set — $message';

      case 'show_board':
        // Fetch actual tasks from Firestore
        final tasks = await _firestoreService.getTasks(userId);
        final pendingTasks = tasks
          .where((t) => t['status'] != 'done')
          .toList();
        
        // Build readable task list
        if (pendingTasks.isEmpty) {
          return 'TASK_LIST_START\nTASK_LIST_END\nNo pending tasks. You are clear.';
        } else {
          final buffer = StringBuffer();
          buffer.writeln('TASK_LIST_START');
          for (int i = 0; i < pendingTasks.length; i++) {
            final t = pendingTasks[i];
            final title = t['title'] ?? 'Untitled';
            final due = t['due_date'] ?? '';
            final priority = t['priority'] ?? 'medium';
            final id = t['id'] ?? '';
            buffer.writeln('$id|$title|$due|$priority');
          }
          buffer.writeln('TASK_LIST_END');
          return buffer.toString();
        }

      case 'query_emails':
        final daysBack = (toolInput['days_back'] as int?) ?? 1;
        final filter = toolInput['filter'] as String? ?? 'all';
        final emails = await _firestoreService.getRecentEmails(
          userId,
          daysBack: daysBack,
          filter: filter,
        );
        if (emails.isEmpty) {
          final label = filter == 'pending_triage' ? 'unprocessed' : filter == 'all' ? '' : '$filter ';
          return 'No ${label}emails found in the last $daysBack day(s).';
        }
        final buf = StringBuffer();
        buf.writeln('${emails.length} email(s) — last $daysBack day(s):\n');
        for (final e in emails) {
          final importance = (e['importance'] ?? 'pending').toString().toUpperCase();
          final subject = e['subject'] ?? 'No subject';
          final from = e['from'] ?? '';
          final summary = e['emailSummary'] ?? e['summary'] ?? '';
          final taskIds = e['taskIds'] as List?;
          final taskCount = taskIds?.length ?? 0;
          buf.writeln('[$importance] $subject');
          buf.writeln('From: $from');
          if (summary.isNotEmpty) buf.writeln(summary);
          if (taskCount > 0) buf.writeln('→ $taskCount task(s) created');
          buf.writeln();
        }
        return buf.toString().trim();

      case 'search_data':
        return '✓ Search coming soon.';

      case 'log_time':
        // Convert Claude's args into a TimeLog doc and persist.
        // Claude may miss optional fields — we fill sensible defaults
        // so the save never fails.
        final kind = (toolInput['kind'] ?? 'routine').toString();
        final durationMin = (toolInput['duration_min'] is int)
            ? toolInput['duration_min'] as int
            : int.tryParse('${toolInput['duration_min']}') ?? 0;
        final categoryId = (toolInput['category_id'] ?? 'admin').toString();
        final activity = (toolInput['activity'] ?? '').toString();
        final dateStr = (toolInput['date'] ?? '').toString();
        // Default to today if Claude didn't set a date. Date is the
        // IST calendar date of the activity.
        DateTime date;
        String dateKey;
        if (dateStr.isNotEmpty) {
          try {
            date = DateTime.parse(dateStr);
          } catch (_) {
            date = DateTime.now();
          }
        } else {
          date = DateTime.now();
        }
        dateKey = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
        // Revenue flag: explicit user override wins, else category default.
        final catDefault = TimeCategories.byId(categoryId)?.defaultRevenue
            ?? false;
        final isRevenue = toolInput['is_revenue'] is bool
            ? toolInput['is_revenue'] as bool
            : catDefault;
        final tLog = TimeLog(
          id: '',
          kind: kind,
          date: date,
          dateKey: dateKey,
          durationMin: durationMin,
          categoryId: categoryId,
          isRevenue: isRevenue,
          activity: activity,
          notes: (toolInput['notes'] as String?)?.trim().isEmpty == true
              ? null
              : toolInput['notes']?.toString(),
          clientName: toolInput['client_name']?.toString(),
          visitContactType: toolInput['visit_contact_type']?.toString(),
          visitPersonName: toolInput['visit_person_name']?.toString(),
          visitCompany: toolInput['visit_company']?.toString(),
          visitLocation: toolInput['visit_location']?.toString(),
          visitDiscussion: toolInput['visit_discussion']?.toString(),
          visitNextSteps: toolInput['visit_next_steps']?.toString(),
          source: 'voice',
        );
        await _firestoreService.createTimeLog(userId: userId, log: tLog);
        final hours = (durationMin / 60).toStringAsFixed(
          durationMin % 60 == 0 ? 0 : 1,
        );
        final label = kind == 'visit' ? 'Visit logged' : 'Time logged';
        return '✓ $label — ${hours}h $activity';

      case 'report_bug':
        // Store the user's verbatim text as the source of truth. Claude's
        // tool input (title/severity/screen) stays too — useful for triage
        // ordering — but `user_text` is what we treat as authoritative.
        // This bypasses Claude's tendency to paraphrase/translate bug reports.
        final bugPayload = {
          ...toolInput,
          if (originalUserText != null && originalUserText.trim().isNotEmpty)
            'user_text': originalUserText.trim(),
        };
        final bugId = await _firestoreService.saveBug(userId, bugPayload);
        final title = (toolInput['title'] ?? 'bug').toString();
        // Keep the confirmation terse — the widget bar will flash this.
        return '✓ Bug logged — $title';

      default:
        return '✓ Action completed.';
    }
  }

  Future<void> sendImageMessage(String imagePath) async {
    final userId = ref.read(activeUserIdProvider);
    final user = ref.read(activeUserProvider);

    if (userId == null || user == null) {
      state = state.copyWith(error: 'No user logged in', isLoading: false);
      return;
    }

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: '[Photo]',
      inputType: 'text',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [userMessage, ...state.messages],
      isLoading: true,
      error: null,
    );

    try {
      final recentData = await _firestoreService.getRecentData(userId);
      final recentTasks = recentData['tasks'] as List<Map<String, dynamic>>;
      final recentThoughts = recentData['thoughts'] as List<Map<String, dynamic>>;

      final responseText = await _claudeService.sendImageMessage(
        userId: userId,
        user: user,
        imagePath: imagePath,
        recentTasks: recentTasks,
        recentThoughts: recentThoughts,
      );

      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'assistant',
        content: responseText,
        inputType: 'text',
        timestamp: DateTime.now(),
      );

      await _firestoreService.saveChatMessage(userId, userMessage.toFirestore());
      await _firestoreService.saveChatMessage(userId, assistantMessage.toFirestore());
      state = state.copyWith(isLoading: false);
    } catch (e) {
      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'assistant',
        content: 'Could not process image. Try again.',
        inputType: 'text',
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [errorMessage, ...state.messages],
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Service Providers
final openAIServiceProvider = Provider((ref) => OpenAIService());
final audioServiceProvider = Provider((ref) => AudioService());

// Chat Provider
final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
