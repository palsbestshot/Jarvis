import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'tool_result'
  final String content;
  final String inputType; // 'text' | 'voice'
  final DateTime timestamp;
  final String? toolName; // if this was a tool action confirmation
  final String? messageType; // 'system', 'morning_briefing', 'nudge', etc.
  final bool isTaskList; // if this message contains task list data

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.inputType,
    required this.timestamp,
    this.toolName,
    this.messageType,
    this.isTaskList = false,
  });

  factory ChatMessage.fromFirestore(Map<String, dynamic> data, String docId) {
    final content = data['content'] as String? ?? '';
    final isTaskList = content.contains('TASK_LIST_START');
    
    return ChatMessage(
      id: docId,
      role: data['role'] as String? ?? 'user',
      content: content,
      inputType: data['input_type'] as String? ?? 'text',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      toolName: data['tool_name'] as String?,
      messageType: data['message_type'] as String?,
      isTaskList: isTaskList,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'role': role,
      'content': content,
      'input_type': inputType,
      'timestamp': timestamp,
      if (toolName != null) 'tool_name': toolName,
      if (messageType != null) 'message_type': messageType,
    };
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isToolResult => role == 'tool_result';

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, content: $content, timestamp: $timestamp, isTaskList: $isTaskList)';
  }
}
