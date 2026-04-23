import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../services/agent_service.dart';
import '../services/tavily_service.dart';

// Agent chat message model for UI display
class AgentChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'thinking' | 'tool_result' | 'approval_request'
  final String content;
  final String? toolName;
  final DateTime timestamp;
  final bool requiresApproval;
  final String? toolCallId; // for tool result messages

  AgentChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.toolName,
    required this.timestamp,
    this.requiresApproval = false,
    this.toolCallId,
  });
}

// Agent pending action model
class AgentPendingAction {
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String description;
  final String? toolCallId;
  final Map<String, dynamic>? rawAssistantMessage;

  AgentPendingAction({
    required this.toolName,
    required this.toolInput,
    required this.description,
    this.toolCallId,
    this.rawAssistantMessage,
  });
}

// Agent state
class AgentState {
  final List<AgentChatMessage> messages;
  final bool isLoading;
  final bool isWaitingApproval;
  final AgentPendingAction? pendingAction;
  final String? error;

  AgentState({
    required this.messages,
    required this.isLoading,
    required this.isWaitingApproval,
    this.pendingAction,
    this.error,
  });

  AgentState copyWith({
    List<AgentChatMessage>? messages,
    bool? isLoading,
    bool? isWaitingApproval,
    AgentPendingAction? pendingAction,
    String? error,
  }) {
    return AgentState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isWaitingApproval: isWaitingApproval ?? this.isWaitingApproval,
      pendingAction: pendingAction ?? this.pendingAction,
      error: error ?? this.error,
    );
  }
}

// Agent Notifier
class AgentNotifier extends StateNotifier<AgentState> {
  final AgentService _agentService;
  final TavilyService _tavilyService;
  final UserProfile _user;
  
  // Maintain RAW OpenAI format conversation history
  List<Map<String, dynamic>> _openAIMessages = [];

  AgentNotifier(this._user)
      : _agentService = AgentService(),
        _tavilyService = TavilyService(),
        super(AgentState(
          messages: [],
          isLoading: false,
          isWaitingApproval: false,
          pendingAction: null,
          error: null,
        ));

  // Clear conversation history
  void clearHistory() {
    _openAIMessages.clear();
    state = state.copyWith(
      messages: [],
      isLoading: false,
      isWaitingApproval: false,
      pendingAction: null,
      error: null,
    );
  }

  Future<void> sendMessage(String text) async {
    try {
      // Add user message to UI
      final userMessage = AgentChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [userMessage, ...state.messages],
        isLoading: true,
        error: null,
      );

      // Add user message to OpenAI history
      _openAIMessages.add({
        'role': 'user',
        'content': text,
      });

      // Call OpenAI with full conversation history
      final response = await _agentService.sendAgentMessage(
        userId: _user.id,
        user: _user,
        messages: _openAIMessages,
      );

      // Handle thinking message if present
      if (response.text != null && response.text!.startsWith('Thinking:')) {
        final thinkingEnd = response.text!.indexOf('\n\n');
        if (thinkingEnd != -1) {
          final thinking = response.text!.substring(0, thinkingEnd).trim();
          final thinkingMessage = AgentChatMessage(
            id: '${DateTime.now().millisecondsSinceEpoch}_thinking',
            role: 'thinking',
            content: thinking,
            timestamp: DateTime.now(),
          );

          state = state.copyWith(
            messages: [thinkingMessage, ...state.messages],
          );
        }
      }

      // Handle tool call
      if (response.hasToolCall && response.toolName != null && response.toolArguments != null) {
        // CRITICAL: Add the raw assistant message to history FIRST
        if (response.rawAssistantMessage != null) {
          _openAIMessages.add(response.rawAssistantMessage!);
        }

        // Convert to AgentChatMessage for UI display
        final assistantChatMessage = AgentChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_tool_call',
          role: 'assistant',
          content: response.text ?? 'Executing ${response.toolName}...',
          toolName: response.toolName,
          timestamp: DateTime.now(),
        );
        
        state = state.copyWith(
          messages: [assistantChatMessage, ...state.messages],
        );
        
        // Check if tool requires approval
        final requiresApproval = _requiresApproval(response.toolName!);
        
        if (requiresApproval) {
          // Create approval request
          final description = _createActionDescription(response.toolName!, response.toolArguments!);
          final pendingAction = AgentPendingAction(
            toolName: response.toolName!,
            toolInput: response.toolArguments!,
            description: description,
            toolCallId: response.toolCallId,
            rawAssistantMessage: response.rawAssistantMessage,
          );

          final approvalMessage = AgentChatMessage(
            id: '${DateTime.now().millisecondsSinceEpoch}_approval',
            role: 'approval_request',
            content: description,
            toolName: response.toolName,
            timestamp: DateTime.now(),
            requiresApproval: true,
          );

          state = state.copyWith(
            messages: [approvalMessage, ...state.messages],
            isWaitingApproval: true,
            pendingAction: pendingAction,
            isLoading: false,
          );
        } else {
          // Execute the tool immediately
          await _executeTool(
            response.toolName!, 
            response.toolArguments!,
            toolCallId: response.toolCallId,
          );
        }
        return;
      }

      // Handle text response
      if (response.text != null && response.text!.isNotEmpty) {
        // Add assistant response to OpenAI history
        _openAIMessages.add({
          'role': 'assistant',
          'content': response.text!,
        });

        final assistantMessage = AgentChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: response.text!,
          timestamp: DateTime.now(),
        );

        state = state.copyWith(
          messages: [assistantMessage, ...state.messages],
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'No response from agent',
        );
      }
    } catch (e) {
      // Remove the last user message that caused the error
      if (_openAIMessages.isNotEmpty &&
          _openAIMessages.last['role'] == 'user') {
        _openAIMessages.removeLast();
      }

      final errorMessage = AgentChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_error',
        role: 'assistant',
        content: 'Something went wrong. Check your API keys and internet connection.',
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [errorMessage, ...state.messages],
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _executeTool(
    String toolName, 
    Map<String, dynamic> toolInput, {
    String? toolCallId,
  }) async {
    try {
      String result;
      
      switch (toolName) {
          case 'web_search':
            result = await _executeWebSearch(toolInput);
            break;
          case 'analyze_url':
            result = await _executeAnalyzeUrl(toolInput);
            break;
          case 'draft_email':
            result = await _executeDraftEmail(toolInput);
            break;
          case 'calculate':
            result = await _executeCalculate(toolInput);
            break;
          case 'summarize':
            result = await _executeSummarize(toolInput);
            break;
          default:
            result = 'Unknown tool: $toolName';
        }

      // Add tool result message to UI
      final toolResultMessage = AgentChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_tool',
        role: 'tool_result',
        content: result,
        toolName: toolName,
        timestamp: DateTime.now(),
        toolCallId: toolCallId,
      );

      state = state.copyWith(
        messages: [toolResultMessage, ...state.messages],
      );

      // Add tool result to OpenAI history with matching tool_call_id
      if (toolCallId != null) {
        _openAIMessages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': result,
        });
      } else {
        // This shouldn't happen, but handle gracefully
        throw Exception('Tool call ID is null for tool: $toolName');
      }

      // Call OpenAI again with updated history
      final finalResponse = await _agentService.sendAgentMessage(
        userId: _user.id,
        user: _user,
        messages: _openAIMessages,
      );

      // Add final assistant response to history
      if (finalResponse.text != null) {
        _openAIMessages.add({
          'role': 'assistant',
          'content': finalResponse.text!,
        });

        final assistantMessage = AgentChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: finalResponse.text!,
          timestamp: DateTime.now(),
        );

        state = state.copyWith(
          messages: [assistantMessage, ...state.messages],
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
        );
      }
    } catch (e) {
      final errorContent = 'Error executing $toolName: ${e.toString()}';
      final errorMessage = AgentChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_error',
        role: 'tool_result',
        content: errorContent,
        toolName: toolName,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [errorMessage, ...state.messages],
        isLoading: false,
      );

      // Also add error as tool result to OpenAI history
      if (toolCallId != null) {
        _openAIMessages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': errorContent,
        });

        // Call OpenAI again with error result
        try {
          final finalResponse = await _agentService.sendAgentMessage(
            userId: _user.id,
            user: _user,
            messages: _openAIMessages,
          );

          // Add final assistant response to history
          if (finalResponse.text != null) {
            _openAIMessages.add({
              'role': 'assistant',
              'content': finalResponse.text!,
            });

            final assistantMessage = AgentChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              role: 'assistant',
              content: finalResponse.text!,
              timestamp: DateTime.now(),
            );

            state = state.copyWith(
              messages: [assistantMessage, ...state.messages],
            );
          }
        } catch (e2) {
          // If OpenAI call fails after tool error, just log it
          print('Error calling OpenAI after tool error: $e2');
        }
      }
    }
  }

  Future<String> _executeWebSearch(Map<String, dynamic> toolInput) async {
    final query = toolInput['query'] as String;
    final numResults = toolInput['num_results'] as int? ?? 5;
    
    try {
      final result = await _tavilyService.search(query, numResults: numResults);
      return _tavilyService.formatResults(result);
    } catch (e) {
      if (e.toString().contains('Tavily API key not configured')) {
        return 'Tavily API key not configured. Please add TAVILY_API_KEY to env.json file. Get a free key at: https://tavily.com';
      }
      rethrow;
    }
  }

  Future<String> _executeAnalyzeUrl(Map<String, dynamic> toolInput) async {
    final url = toolInput['url'] as String;
    final question = toolInput['question'] as String?;
    
    try {
      // Simple HTTP GET to fetch URL content
      // Note: This is a basic implementation - in production you might want to use a proper HTML parser
      final response = await _tavilyService.search(url, numResults: 1);
      
      if (response.results.isNotEmpty) {
        final result = response.results.first;
        final content = result.content;
        
        if (question != null && question.isNotEmpty) {
          return 'URL: $url\nQuestion: $question\n\nContent (first 2000 chars):\n${content.length > 2000 ? content.substring(0, 2000) + '...' : content}';
        } else {
          return 'URL: $url\n\nContent (first 2000 chars):\n${content.length > 2000 ? content.substring(0, 2000) + '...' : content}';
        }
      } else {
        return 'No content found for URL: $url';
      }
    } catch (e) {
      return 'Error analyzing URL $url: ${e.toString()}';
    }
  }

  Future<String> _executeDraftEmail(Map<String, dynamic> toolInput) async {
    final to = toolInput['to'] as String;
    final subject = toolInput['subject'] as String;
    final body = toolInput['body'] as String;
    final tone = toolInput['tone'] as String? ?? 'formal';
    
    return '''
Email Draft for Review:
To: $to
Subject: $subject
Tone: $tone

Body:
$body

Note: This is a draft. Review and edit before sending.
''';
  }

  Future<String> _executeCalculate(Map<String, dynamic> toolInput) async {
    final expression = toolInput['expression'] as String;
    
    try {
      // Simple arithmetic evaluation
      // Note: For production, use a proper math parser library
      final result = _evaluateSimpleExpression(expression);
      return 'Calculation: $expression = $result';
    } catch (e) {
      return 'Error calculating expression "$expression": ${e.toString()}';
    }
  }

  Future<String> _executeSummarize(Map<String, dynamic> toolInput) async {
    final content = toolInput['content'] as String;
    final length = toolInput['length'] as String? ?? 'medium';
    
    // For Phase 5, just return a simple summary
    // In Phase 6, this could call GPT-4o for better summarization
    final maxLength = switch (length) {
      'brief' => 100,
      'medium' => 250,
      'detailed' => 500,
      _ => 250,
    };
    
    if (content.length <= maxLength) {
      return 'Summary ($length):\n$content';
    } else {
      return 'Summary ($length):\n${content.substring(0, maxLength)}...';
    }
  }

  double _evaluateSimpleExpression(String expression) {
    // Very basic arithmetic evaluation for Phase 5
    // Supports only +, -, *, / with integers
    expression = expression.replaceAll(' ', '');
    
    // Find operator
    final operators = ['+', '-', '*', '/'];
    String? operator;
    int operatorIndex = -1;
    
    for (final op in operators) {
      final index = expression.indexOf(op);
      if (index > 0) {
        operator = op;
        operatorIndex = index;
        break;
      }
    }
    
    if (operator == null) {
      throw Exception('No valid operator found in expression');
    }
    
    final leftStr = expression.substring(0, operatorIndex);
    final rightStr = expression.substring(operatorIndex + 1);
    
    final left = double.tryParse(leftStr) ?? 0;
    final right = double.tryParse(rightStr) ?? 0;
    
    return switch (operator) {
      '+' => left + right,
      '-' => left - right,
      '*' => left * right,
      '/' => right != 0 ? left / right : throw Exception('Division by zero'),
      _ => throw Exception('Unknown operator: $operator'),
    };
  }

  Future<void> approveAction() async {
    if (state.pendingAction == null) return;
    
    final pendingAction = state.pendingAction!;
    
    state = state.copyWith(
      isWaitingApproval: false,
      pendingAction: null,
    );
    
    await _executeTool(
      pendingAction.toolName, 
      pendingAction.toolInput,
      toolCallId: pendingAction.toolCallId,
    );
  }

  Future<void> rejectAction() async {
    final rejectionMessage = AgentChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'assistant',
      content: 'Action cancelled.',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [rejectionMessage, ...state.messages],
      isWaitingApproval: false,
      pendingAction: null,
    );
  }

  bool _requiresApproval(String toolName) {
    // Only draft_email requires approval (medium risk)
    return toolName == 'draft_email';
  }

  String _createActionDescription(String toolName, Map<String, dynamic> toolInput) {
    switch (toolName) {
      case 'draft_email':
        return 'Draft an email to ${toolInput['to']} with subject "${toolInput['subject']}"';
      default:
        return 'Unknown tool: $toolName';
    }
  }
}

// Provider
final agentNotifierProvider = StateNotifierProvider.family<AgentNotifier, AgentState, UserProfile>(
  (ref, user) => AgentNotifier(user),
);
