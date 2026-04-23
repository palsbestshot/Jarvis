import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/user_profile.dart';
import '../models/agent_response.dart';

class AgentService {
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';
  static const String _model = 'gpt-4o-2024-11-20';

  Future<AgentServiceResponse> sendAgentMessage({
    required String userId,
    required UserProfile user,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      // Build system prompt
      final systemPrompt = _buildSystemPrompt(user);
      
      // Build tools array
      final tools = _buildToolsArray();

      // Add system prompt at the beginning of messages
      final allMessages = [
        {'role': 'system', 'content': systemPrompt},
        ...messages,
      ];

      // Make POST request to OpenAI
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Authorization': 'Bearer ${AppConstants.openaiApiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 2048,
          'messages': allMessages,
          'tools': tools,
          'tool_choice': 'auto',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('OpenAI API error: ${response.statusCode} - ${response.body}');
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseResponse(responseData);
    } catch (e) {
      rethrow;
    }
  }

  String _buildSystemPrompt(UserProfile user) {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} IST';

    return '''
You are JARVIS Agent, ${user.name}'s personal AI agent.
Today: $date. Current time: $time.

You are the AGENT mode — more powerful than chat mode.
You can search the web, analyze information, and execute 
multi-step tasks. You think step by step and show your work.

PERSONALITY: You are JARVIS from Iron Man — precise, efficient, 
and deeply personal. You know ${user.name}'s life, preferences, 
and history. You're proactive, anticipate needs, and offer 
solutions before being asked. You're witty but not overly casual. 
You respect privacy and boundaries. You're a partner, not just a tool.

AGENT RULES:
- Show your thinking with "Thinking: ..." before acting
- For web searches, explain what you're searching and why
- Present findings clearly without markdown
- Ask for approval before taking irreversible actions
- Be thorough but concise in final answers

AVAILABLE TOOLS:
web_search: Search the web for current information
analyze_url: Fetch and analyze a specific URL
draft_email: Create an email draft for review
calculate: Perform calculations
summarize: Summarize long content
''';
  }

  List<Map<String, dynamic>> _buildToolsArray() {
    final tools = [
      {
        'type': 'function',
        'function': {
          'name': 'web_search',
          'description': 'Search the web for current information',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'The search query',
              },
              'num_results': {
                'type': 'integer',
                'description': 'Number of results to return (default: 5)',
                'default': 5,
              },
            },
            'required': ['query'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'analyze_url',
          'description': 'Fetch and analyze content from a URL',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': 'The URL to analyze',
              },
              'question': {
                'type': 'string',
                'description': 'What to look for in the content',
              },
            },
            'required': ['url'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'draft_email',
          'description': 'Create an email draft for review before sending',
          'parameters': {
            'type': 'object',
            'properties': {
              'to': {
                'type': 'string',
                'description': 'Recipient email address',
              },
              'subject': {
                'type': 'string',
                'description': 'Email subject',
              },
              'body': {
                'type': 'string',
                'description': 'Email body content',
              },
              'tone': {
                'type': 'string',
                'description': 'Email tone',
                'enum': ['formal', 'friendly', 'concise'],
              },
            },
            'required': ['to', 'subject', 'body'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'calculate',
          'description': 'Perform mathematical calculations',
          'parameters': {
            'type': 'object',
            'properties': {
              'expression': {
                'type': 'string',
                'description': 'Mathematical expression to calculate',
              },
            },
            'required': ['expression'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'summarize',
          'description': 'Summarize provided text content',
          'parameters': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Text content to summarize',
              },
              'length': {
                'type': 'string',
                'description': 'Summary length',
                'enum': ['brief', 'medium', 'detailed'],
              },
            },
            'required': ['content'],
          },
        },
      },
    ];

    // Add PC Agent tools if PC is online (this will be checked by the provider)
    // The provider will filter these out if PC is offline
    final pcTools = [
      {
        'type': 'function',
        'function': {
          'name': 'pc_scrape',
          'description': 'Scrape a website on the home PC for content or data',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': 'The URL to scrape',
              },
              'extract': {
                'type': 'string',
                'description': 'What to look for on the page',
              },
              'format': {
                'type': 'string',
                'description': 'Output format',
                'enum': ['text', 'structured'],
                'default': 'text',
              },
            },
            'required': ['url'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_excel',
          'description': 'Create an Excel file on the home PC desktop',
          'parameters': {
            'type': 'object',
            'properties': {
              'filename': {
                'type': 'string',
                'description': 'Name of the Excel file (without .xlsx)',
              },
              'description': {
                'type': 'string',
                'description': 'What data to put in the Excel file',
              },
            },
            'required': ['filename'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_gmail_summary',
          'description': 'Get a summary of recent emails from JARVIS Gmail inbox',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_results': {
                'type': 'integer',
                'description': 'Number of emails to summarize (default: 10)',
                'default': 10,
              },
            },
            'required': [],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_gmail_unread',
          'description': 'Get unread emails from JARVIS Gmail inbox',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_results': {
                'type': 'integer',
                'description': 'Number of unread emails to fetch (default: 10)',
                'default': 10,
              },
            },
            'required': [],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_gmail_search',
          'description': 'Search Gmail for specific emails by query (e.g. "from:boss subject:deadline")',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Gmail search query',
              },
              'max_results': {
                'type': 'integer',
                'description': 'Max results (default: 10)',
                'default': 10,
              },
            },
            'required': ['query'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_tasks_from_email',
          'description': 'Extract action items from a specific email and create tasks in Firestore',
          'parameters': {
            'type': 'object',
            'properties': {
              'email_id': {
                'type': 'string',
                'description': 'Gmail message ID to extract tasks from',
              },
              'user_id': {
                'type': 'string',
                'description': 'User ID (pallav or rakhi)',
              },
            },
            'required': ['email_id', 'user_id'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_generate_tasks',
          'description': 'Generate and add smart daily tasks based on context',
          'parameters': {
            'type': 'object',
            'properties': {
              'context': {
                'type': 'string',
                'description': "What's happening today or context for task generation",
              },
            },
            'required': ['context'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_job_search',
          'description': 'Search for job listings on LinkedIn',
          'parameters': {
            'type': 'object',
            'properties': {
              'keywords': {
                'type': 'string',
                'description': 'Job search keywords',
              },
              'location': {
                'type': 'string',
                'description': 'Location for job search (default: Hyderabad)',
                'default': 'Hyderabad',
              },
            },
            'required': ['keywords'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_email_digest',
          'description': 'Get JARVIS email intelligence digest — shows recent emails analyzed with importance, summaries, and suggested actions',
          'parameters': {
            'type': 'object',
            'properties': {
              'limit': {
                'type': 'integer',
                'description': 'Number of recent digest entries (default: 10)',
                'default': 10,
              },
            },
            'required': [],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_email_pending_tasks',
          'description': 'Get all open tasks created from emails, with how-to-close instructions and suggested replies',
          'parameters': {
            'type': 'object',
            'properties': {},
            'required': [],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'pc_email_scan_now',
          'description': 'Trigger an immediate email scan — checks for new emails, triages them, and creates tasks for important ones',
          'parameters': {
            'type': 'object',
            'properties': {},
            'required': [],
          },
        },
      },
    ];

    // Add all tools (provider will filter PC tools if PC is offline)
    tools.addAll(pcTools);
    return tools;
  }

  AgentServiceResponse _parseResponse(Map<String, dynamic> responseData) {
    final choices = responseData['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('No response from OpenAI');
    }

    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String;

    // Extract thinking from content if present
    String? thinking;
    String? text = message['content'] as String?;
    
    if (text != null && text.startsWith('Thinking:')) {
      final thinkingEnd = text.indexOf('\n\n');
      if (thinkingEnd != -1) {
        thinking = text.substring(0, thinkingEnd).trim();
        text = text.substring(thinkingEnd).trim();
      }
    }

    // Check for tool calls
    if (finishReason == 'tool_calls') {
      final toolCalls = message['tool_calls'] as List?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        final toolCall = toolCalls.first as Map<String, dynamic>;
        final function = toolCall['function'] as Map<String, dynamic>;
        
        return AgentServiceResponse(
          text: text,
          hasToolCall: true,
          toolCallId: toolCall['id'] as String,
          toolName: function['name'] as String,
          toolArguments: jsonDecode(function['arguments'].toString()) as Map<String, dynamic>,
          rawAssistantMessage: message,
        );
      }
    }

    // No tool call - regular text response
    return AgentServiceResponse(
      text: text,
      hasToolCall: false,
      toolCallId: null,
      toolName: null,
      toolArguments: null,
      rawAssistantMessage: null,
    );
  }
}

class AgentServiceResponse {
  final String? text;           // final text response
  final bool hasToolCall;
  final String? toolCallId;     // "call_abc123"
  final String? toolName;       // "web_search"
  final Map<String, dynamic>? toolArguments;  // parsed JSON args
  final Map<String, dynamic>? rawAssistantMessage; // FULL message object from OpenAI

  AgentServiceResponse({
    this.text,
    required this.hasToolCall,
    this.toolCallId,
    this.toolName,
    this.toolArguments,
    this.rawAssistantMessage,
  });
}