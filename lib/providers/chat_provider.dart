import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
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

      // 1. Transcribe audio using Whisper. Android has a real file path;
      // web has a blob URL plus cached bytes in audioService — route
      // each to the right transcribe method. Both ultimately land at
      // Whisper (direct on native, through the aiTranscribe Function
      // proxy on web).
      String transcript;
      try {
        if (kIsWeb) {
          final bytes = audioService.lastRecordedBytes;
          if (bytes == null || bytes.isEmpty) {
            throw Exception('No audio bytes captured — microphone blocked?');
          }
          transcript = await openAIService.transcribeAudioBytes(
            bytes,
            mimeType: 'audio/webm',
          );
        } else {
          transcript = await openAIService.transcribeAudio(filePath);
        }
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
        return await _handleSaveMeal(userId, toolInput);

      case 'query_dishes':
        return await _handleQueryDishes(userId, toolInput);

      case 'suggest_dish_from_ingredients':
        return _handleSuggestDish(toolInput);

      case 'plan_day_meals':
        return await _handlePlanDayMeals(userId, toolInput);

      case 'plan_week_meals':
        return await _handlePlanWeekMeals(userId, toolInput);

      case 'get_meal_plan_range':
        return await _handleGetMealPlanRange(userId, toolInput);

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

  // ── Meal-plan tool handlers (Rakhi only) ─────────────────────────

  /// Fuzzy-match a dish name against Rakhi's catalog. Returns the
  /// matching dish id, or null if no reasonable match exists.
  /// Matching is case-insensitive and accepts prefix / contains matches.
  Future<String?> _findDishByName(String userId, String name) async {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    try {
      final catalog = await _firestoreService.getDishCatalog(userId);
      // Exact match first.
      for (final d in catalog) {
        final n = (d['name'] ?? '').toString().toLowerCase();
        if (n == trimmed) return d['id']?.toString();
      }
      // Contains / prefix fallback.
      for (final d in catalog) {
        final n = (d['name'] ?? '').toString().toLowerCase();
        if (n.contains(trimmed) || trimmed.contains(n)) {
          return d['id']?.toString();
        }
      }
    } catch (_) {/* fall through to null */}
    return null;
  }

  /// Plan a single meal slot. If the dish isn't in the catalog, create
  /// it first (tagged 'custom') so future suggestions can surface it.
  Future<String> _handleSaveMeal(
    String userId,
    Map<String, dynamic> input,
  ) async {
    final mealType = (input['meal_type'] ?? 'lunch').toString();
    final dishName = (input['dish_name'] ?? '').toString().trim();
    if (dishName.isEmpty) {
      return '✗ No dish name given.';
    }
    final dateRaw = (input['date'] ?? '').toString().trim();
    final dateKey = _resolveDateKey(dateRaw);

    // Find existing dish or auto-create a custom one.
    var dishId = await _findDishByName(userId, dishName);
    if (dishId == null) {
      dishId = await _firestoreService.createDish(userId, {
        'name': dishName,
        'meal_types': [mealType],
        'prep_minutes': 20,
        'tags': ['custom'],
        'ingredients': <String>[],
      });
    }
    final notes = (input['notes'] ?? '').toString().trim();
    await _firestoreService.setMealSlot(
      userId,
      dateKey,
      mealType,
      {
        'dish_id': dishId,
        if (notes.isNotEmpty) 'notes': notes,
      },
    );
    await _firestoreService.incrementDishTimesUsed(userId, dishId);
    return '✓ Meal planned — $dateKey $mealType: $dishName';
  }

  /// Pull dishes from Rakhi's catalog for Claude to consume. Filters
  /// are applied client-side (catalog is small).
  Future<String> _handleQueryDishes(
    String userId,
    Map<String, dynamic> input,
  ) async {
    final mealType = (input['meal_type'] ?? '').toString();
    final tag = (input['tag'] ?? '').toString().toLowerCase();
    final limitRaw = input['limit'];
    final limit = (limitRaw is int)
        ? limitRaw
        : int.tryParse('$limitRaw') ?? 30;

    final all = await _firestoreService.getDishCatalog(userId);
    List<Map<String, dynamic>> filtered = all;
    if (mealType.isNotEmpty) {
      filtered = filtered.where((d) {
        final mt = (d['meal_types'] as List?)?.cast<dynamic>() ?? [];
        return mt.any((v) => v.toString() == mealType);
      }).toList();
    }
    if (tag.isNotEmpty) {
      filtered = filtered.where((d) {
        final tags = (d['tags'] as List?)?.cast<dynamic>() ?? [];
        return tags.any((v) => v.toString().toLowerCase() == tag);
      }).toList();
    }
    final capped = filtered.take(limit.clamp(1, 80)).toList();
    // Return a compact text blob — Claude reads tool_result as text.
    final buf = StringBuffer();
    buf.writeln('${capped.length} dishes in catalog:');
    for (final d in capped) {
      final name = d['name'] ?? '';
      final prep = d['prep_minutes'] ?? '?';
      final mt = ((d['meal_types'] as List?) ?? []).join(',');
      final tags = ((d['tags'] as List?) ?? []).join(',');
      final ing = ((d['ingredients'] as List?) ?? []).join(',');
      final used = d['times_used'] ?? 0;
      buf.writeln(
          '- $name | ${prep}min | $mt | tags:$tags | ing:$ing | used:$used');
    }
    return buf.toString();
  }

  /// Render Claude's dish suggestions as a chat-friendly text block.
  /// No Firestore writes — this is a suggestion surface. If Rakhi picks
  /// one, her next message triggers save_meal for the chosen dish.
  String _handleSuggestDish(Map<String, dynamic> input) {
    final suggestions =
        (input['suggestions'] as List?)?.cast<dynamic>() ?? [];
    if (suggestions.isEmpty) {
      return 'No suggestions generated.';
    }
    final buf = StringBuffer();
    buf.writeln('Here are ${suggestions.length} ideas:');
    for (var i = 0; i < suggestions.length; i++) {
      final s = suggestions[i] as Map<String, dynamic>;
      final name = s['dish_name'] ?? '';
      final why = s['why'] ?? '';
      final missing =
          ((s['missing_ingredients'] as List?)?.cast<dynamic>() ?? [])
              .join(', ');
      buf.writeln('${i + 1}. $name');
      if (why.toString().isNotEmpty) buf.writeln('   Why: $why');
      if (missing.isNotEmpty) buf.writeln('   Still need: $missing');
    }
    buf.writeln('\nTell me which one and I\'ll add it to the slot.');
    return buf.toString();
  }

  /// Plan multiple meals in one go. Each plan entry gets fuzzy-matched
  /// against the catalog (auto-create if no match) and written to the
  /// meal_plans doc. Revenue-neutral — just a batched save_meal.
  Future<String> _handlePlanDayMeals(
    String userId,
    Map<String, dynamic> input,
  ) async {
    final dateKey = _resolveDateKey((input['date'] ?? '').toString());
    final plan = (input['plan'] as List?)?.cast<dynamic>() ?? [];
    if (plan.isEmpty) {
      return '✗ No plan entries received.';
    }
    final savedParts = <String>[];
    for (final entry in plan) {
      if (entry is! Map<String, dynamic>) continue;
      final slot = (entry['slot'] ?? '').toString();
      final dishName = (entry['dish_name'] ?? '').toString().trim();
      if (slot.isEmpty || dishName.isEmpty) continue;
      var dishId = await _findDishByName(userId, dishName);
      dishId ??= await _firestoreService.createDish(userId, {
        'name': dishName,
        'meal_types': [slot],
        'prep_minutes': 20,
        'tags': ['custom'],
        'ingredients': <String>[],
      });
      final notes = (entry['notes'] ?? '').toString().trim();
      await _firestoreService.setMealSlot(userId, dateKey, slot, {
        'dish_id': dishId,
        if (notes.isNotEmpty) 'notes': notes,
      });
      await _firestoreService.incrementDishTimesUsed(userId, dishId);
      savedParts.add('$slot: $dishName');
    }
    if (savedParts.isEmpty) {
      return '✗ Plan had no valid entries.';
    }
    return '✓ Day planned $dateKey — ${savedParts.join(" · ")}';
  }

  /// Read Rakhi's already-planned meals in a date range so Claude can
  /// answer "what am I cooking today", "what are this week's calories",
  /// "nutrition for Monday". Joins meal_plans docs with dish_catalog so
  /// each slot comes back with the RESOLVED dish name + tags + prep
  /// minutes (Claude doesn't see raw dish_ids). Defaults single-day to
  /// today, and single-bound ranges to from_date only.
  Future<String> _handleGetMealPlanRange(
    String userId,
    Map<String, dynamic> input,
  ) async {
    final today = _resolveDateKey('');
    final from = _resolveDateKey((input['from_date'] ?? '').toString());
    final toRaw = (input['to_date'] ?? '').toString().trim();
    final to = toRaw.isEmpty ? from : _resolveDateKey(toRaw);

    // Pull plans + catalog in parallel.
    final results = await Future.wait([
      _firestoreService.getMealPlanRange(userId, from, to),
      _firestoreService.getDishCatalog(userId),
    ]);
    final plans = results[0];
    final catalog = results[1];
    final dishById = <String, Map<String, dynamic>>{};
    for (final d in catalog) {
      final id = (d['id'] ?? '').toString();
      if (id.isNotEmpty) dishById[id] = d;
    }

    const slotLabels = {
      'breakfast': 'Breakfast',
      'brunch': 'Brunch',
      'lunch': 'Lunch',
      'eve_snacks': 'Eve snacks',
      'dinner': 'Dinner',
    };

    // Index plans by date so we can iterate every day in the range even
    // when some days have no doc.
    final byDate = <String, Map<String, dynamic>>{};
    for (final p in plans) {
      byDate[(p['date_key'] ?? p['id'] ?? '').toString()] = p;
    }

    final days = <Map<String, dynamic>>[];
    var cursor = DateTime.parse(from);
    final end = DateTime.parse(to);
    while (!cursor.isAfter(end)) {
      String two(int n) => n.toString().padLeft(2, '0');
      final dateKey =
          '${cursor.year}-${two(cursor.month)}-${two(cursor.day)}';
      final plan = byDate[dateKey];
      final slots = <Map<String, dynamic>>[];
      if (plan != null) {
        for (final slotKey in slotLabels.keys) {
          final raw = plan[slotKey];
          if (raw is! Map) continue;
          final dishId = (raw['dish_id'] ?? '').toString();
          final notes = (raw['notes'] ?? '').toString();
          final dish = dishById[dishId];
          slots.add({
            'slot': slotKey,
            'slot_label': slotLabels[slotKey],
            'dish_name': dish?['name'] ??
                (dishId.isNotEmpty ? '(unknown dish: $dishId)' : '(empty)'),
            if (dish?['prep_minutes'] != null)
              'prep_minutes': dish!['prep_minutes'],
            if (dish?['tags'] is List) 'tags': dish!['tags'],
            if (dish?['ingredients'] is List)
              'ingredients': dish!['ingredients'],
            if (notes.isNotEmpty) 'notes': notes,
          });
        }
      }
      days.add({
        'date': dateKey,
        'weekday':
            ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][cursor.weekday - 1],
        'is_today': dateKey == today,
        'planned_slots': slots,
      });
      cursor = cursor.add(const Duration(days: 1));
    }

    final plannedDayCount = days.where(
      (d) => (d['planned_slots'] as List).isNotEmpty,
    ).length;

    // JSON-ish return so Claude can see structure. The chat surface
    // shows this verbatim, but Claude uses it as tool_result input for
    // the next turn where it composes Rakhi-facing prose.
    return jsonEncode({
      'from_date': from,
      'to_date': to,
      'days': days,
      'planned_day_count': plannedDayCount,
      'total_days': days.length,
    });
  }

  /// Apply Claude's ingredient-driven 7-day plan to Firestore. Each
  /// entry in `days` has an explicit date and a list of slots to fill,
  /// so we just iterate and write. Skips days that already have any
  /// slot planned unless `overwrite_existing` is true. Fuzzy-matches
  /// dish names against Rakhi's catalog and auto-creates a custom
  /// dish entry for anything new Claude invented to use her produce.
  Future<String> _handlePlanWeekMeals(
    String userId,
    Map<String, dynamic> input,
  ) async {
    final days = (input['days'] as List?)?.cast<dynamic>() ?? [];
    final overwrite = input['overwrite_existing'] == true;
    final summary = (input['summary'] ?? '').toString().trim();
    final weekStart = (input['week_start'] ?? '').toString().trim();
    if (days.isEmpty) {
      return '✗ No days in the week plan.';
    }

    // Pre-load existing plans for the date range so the skip-check
    // doesn't round-trip once per day.
    final dateKeys = <String>[];
    for (final d in days) {
      if (d is Map<String, dynamic>) {
        final dk = (d['date'] ?? '').toString().trim();
        if (dk.isNotEmpty) dateKeys.add(dk);
      }
    }
    final existingSnaps = <String, Map<String, dynamic>>{};
    if (dateKeys.isNotEmpty) {
      try {
        final sorted = [...dateKeys]..sort();
        final existing = await _firestoreService.getMealPlanRange(
          userId,
          sorted.first,
          sorted.last,
        );
        for (final plan in existing) {
          existingSnaps[(plan['date_key'] ?? plan['id'] ?? '').toString()] =
              plan;
        }
      } catch (_) {/* non-fatal */}
    }

    int daysWritten = 0;
    int daysSkipped = 0;
    int dishesCreated = 0;
    for (final entry in days) {
      if (entry is! Map<String, dynamic>) continue;
      final dateKey = (entry['date'] ?? '').toString().trim();
      final slots = (entry['slots'] as List?)?.cast<dynamic>() ?? [];
      if (dateKey.isEmpty || slots.isEmpty) continue;

      if (!overwrite) {
        final existing = existingSnaps[dateKey];
        final hasAny = existing != null &&
            ['breakfast', 'brunch', 'lunch', 'eve_snacks', 'dinner']
                .any((k) => existing[k] is Map);
        if (hasAny) {
          daysSkipped++;
          continue;
        }
      }

      var wroteAny = false;
      for (final slotEntry in slots) {
        if (slotEntry is! Map<String, dynamic>) continue;
        final slot = (slotEntry['slot'] ?? '').toString();
        final dishName = (slotEntry['dish_name'] ?? '').toString().trim();
        if (slot.isEmpty || dishName.isEmpty) continue;

        var dishId = await _findDishByName(userId, dishName);
        if (dishId == null) {
          // Pull through any ingredients Claude flagged so the catalog
          // entry is useful next time she queries by ingredient.
          final rawUses = (slotEntry['uses_ingredients'] as List?)
                  ?.cast<dynamic>() ??
              const [];
          final ingredients = rawUses
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          dishId = await _firestoreService.createDish(userId, {
            'name': dishName,
            'meal_types': [slot],
            'prep_minutes': 25,
            'tags': ['custom', 'weekly-plan'],
            'ingredients': ingredients,
          });
          dishesCreated++;
        }
        final notes = (slotEntry['notes'] ?? '').toString().trim();
        await _firestoreService.setMealSlot(userId, dateKey, slot, {
          'dish_id': dishId,
          if (notes.isNotEmpty) 'notes': notes,
        });
        await _firestoreService.incrementDishTimesUsed(userId, dishId);
        wroteAny = true;
      }
      if (wroteAny) daysWritten++;
    }

    final startLabel = weekStart.isNotEmpty ? weekStart : 'this week';
    final parts = <String>['✓ Week plan saved ($startLabel) — $daysWritten days'];
    if (daysSkipped > 0) parts.add('skipped $daysSkipped already-planned');
    if (dishesCreated > 0) parts.add('$dishesCreated new dishes added');
    if (summary.isNotEmpty) parts.add('— $summary');
    return parts.join(' · ');
  }

  /// Normalise a YYYY-MM-DD string. Falls back to today if empty or
  /// unparseable. Used by save_meal + plan_day_meals.
  String _resolveDateKey(String raw) {
    final trimmed = raw.trim();
    DateTime d;
    if (trimmed.isEmpty) {
      d = DateTime.now();
    } else {
      try {
        d = DateTime.parse(trimmed);
      } catch (_) {
        d = DateTime.now();
      }
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
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
