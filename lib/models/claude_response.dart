class ClaudeResponse {
  final String? text; // AI text reply
  final String? toolName; // tool called, if any
  final Map<String, dynamic>? toolInput; // tool parameters
  final bool hasToolCall;

  const ClaudeResponse({
    this.text,
    this.toolName,
    this.toolInput,
    required this.hasToolCall,
  });

  factory ClaudeResponse.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as List<dynamic>? ?? [];
    
    String? text;
    String? toolName;
    Map<String, dynamic>? toolInput;
    bool hasToolCall = false;

    for (final block in content) {
      if (block['type'] == 'text') {
        text = block['text'] as String?;
      } else if (block['type'] == 'tool_use') {
        hasToolCall = true;
        toolName = block['name'] as String?;
        toolInput = Map<String, dynamic>.from(block['input'] as Map? ?? {});
      }
    }

    return ClaudeResponse(
      text: text,
      toolName: toolName,
      toolInput: toolInput,
      hasToolCall: hasToolCall,
    );
  }

  @override
  String toString() {
    return 'ClaudeResponse(text: $text, toolName: $toolName, hasToolCall: $hasToolCall)';
  }
}