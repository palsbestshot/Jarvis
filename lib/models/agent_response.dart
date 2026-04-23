// Agent response model for GPT-4o agent service
class AgentResponse {
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? toolInput;
  final bool hasToolCall;
  final String? thinking; // extracted from "Thinking: ..." prefix
  final String? toolCallId;      // ADD THIS — the id from GPT-4o
  final Map<String, dynamic>? rawAssistantMessage; // ADD THIS — full message object

  AgentResponse({
    this.text,
    this.toolName,
    this.toolInput,
    required this.hasToolCall,
    this.thinking,
    this.toolCallId,
    this.rawAssistantMessage,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      text: json['text'],
      toolName: json['toolName'],
      toolInput: json['toolInput'] != null 
          ? Map<String, dynamic>.from(json['toolInput'])
          : null,
      hasToolCall: json['hasToolCall'] ?? false,
      thinking: json['thinking'],
      toolCallId: json['toolCallId'],
      rawAssistantMessage: json['rawAssistantMessage'] != null
          ? Map<String, dynamic>.from(json['rawAssistantMessage'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'toolName': toolName,
      'toolInput': toolInput,
      'hasToolCall': hasToolCall,
      'thinking': thinking,
      'toolCallId': toolCallId,
      'rawAssistantMessage': rawAssistantMessage,
    };
  }
}

// Agent message model for conversation history
class AgentMessage {
  final String role; // 'user' | 'assistant' | 'tool'
  final String content;
  final String? toolCallId;
  final String? toolName;
  final Map<String, dynamic>? rawMessage; // stores full assistant message for tool calls

  AgentMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
    this.rawMessage,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'role': role,
      'content': content,
    };
    
    if (toolCallId != null) {
      json['tool_call_id'] = toolCallId!;
    }
    
    if (toolName != null) {
      json['tool_name'] = toolName!;
    }
    
    if (rawMessage != null) {
      json['raw_message'] = rawMessage!;
    }
    
    return json;
  }

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    return AgentMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      toolCallId: json['tool_call_id'] as String?,
      toolName: json['tool_name'] as String?,
      rawMessage: json['raw_message'] != null
          ? Map<String, dynamic>.from(json['raw_message'])
          : null,
    );
  }
}