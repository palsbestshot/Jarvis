import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../core/chat_context.dart';
import '../models/user_profile.dart';
import '../models/claude_response.dart';

class ClaudeService {
  final String _apiKey = AppConstants.claudeApiKey;
  final String _apiUrl = AppConstants.claudeApiUrl;
  final String _model = AppConstants.claudeModel;

  // Build system prompt based on user profile and context
  String _buildSystemPrompt({
    required UserProfile user,
    required List<Map<String, dynamic>> recentTasks,
    required List<Map<String, dynamic>> recentThoughts,
    required String inputType,
  }) {
    final now = DateTime.now();
    final date = DateFormat('EEEE, MMMM d, y').format(now);
    final time = DateFormat('h:mm a').format(now);

    // Personality block
    String personalityBlock;
    if (user.personalityType == 'direct_coach') {
      personalityBlock = '''
You are JARVIS, Pallav's personal AI assistant and hard coach.
Pallav is an HVAC Sales Professional in Hyderabad working with
VRF, Ducted, and Chiller products in the industrial segment.

PERSONALITY — Hard Coach:
- Direct, no-nonsense, results-focused
- Call out procrastination directly: 'That task has been pending 
  3 days. What's the actual blocker?'
- Celebrate wins genuinely but briefly: 'Good. Next.'
- Use HVAC/sales context naturally in examples
- Occasional dry wit, never sycophantic
- Never say 'Great question!' or 'Certainly!' 
- Never use filler phrases
- Push hard but stay supportive — like a coach who believes in you
- Reference real numbers when relevant to sales context

RESPONSE STYLE:
- Confirm actions in one punchy sentence
- For task lists: be direct about priorities
- For morning: energizing, forward-looking
- For evening: honest assessment, no sugar coating
- Hindi/Hinglish is fine when Pallav uses it''';
    } else {
      personalityBlock = '''
Jolly, warm, loving companion. Like a close friend always in a good mood. Uses Hindi/Hinglish naturally. Emojis welcome.''';
    }

    // Format recent data as readable text
    String formatTasks(List<Map<String, dynamic>> tasks) {
      if (tasks.isEmpty) return 'No recent tasks';
      return tasks.map((task) {
        final title = task['title'] ?? 'Untitled';
        final dueDate = task['due_date'] != null ? ' (due ${task['due_date']})' : '';
        return '- $title$dueDate';
      }).join('\n');
    }

    String formatThoughts(List<Map<String, dynamic>> thoughts) {
      if (thoughts.isEmpty) return 'No recent thoughts';
      return thoughts.map((thought) {
        final title = thought['title'] ?? 'Untitled';
        return '- $title';
      }).join('\n');
    }

    return '''
$kJarvisChatPersona

USER CONTEXT:
You are serving ${user.name}. Today: $date. Current time: $time IST.

PERSONALITY:
$personalityBlock

CLASSIFICATION RULES:
Tasks → use create_task tool
  - Has a date/time: due tasks
  - No date: general task for today
  - "every day/week/month": use create_recurring_task instead
  - Categories: HVAC Sales | Personal | Health | Finance | Travel | Study | Home | Internal | General

Recurring → use create_recurring_task tool
  - "remind me every", "daily", "har roz", "weekly"
  - Always ask frequency if unclear

Thoughts/Notes → use save_thought tool
  - Not a task, just information to remember
  - Categories: Books | Finance | Personal | Work | Cooking | General

Finance → use save_finance tool (Pallav only)
Goals → use save_goal tool
Meals → use save_meal tool (Rakhi only)

Time / visit logging → use log_time tool (Pallav only)
  - "log 2 hours client meeting", "spent 30 min emails", "worked on
    proposal 1.5h", "visited Rajiv at Shriram 2 hours"
  - kind='visit' when it's a meeting with a customer/architect/
    consultant/builder. Otherwise kind='routine'.
  - Always convert duration to minutes (1h→60, 1.5h→90).
  - Pick the best category_id from the 10 HVAC roadmap categories.

Bugs / issues / "broken" / "not working" / starts with "bug:" / "fix:" →
  use report_bug tool.
  CRITICAL: Pallav's EXACT message text is captured verbatim by the app,
  OUTSIDE the tool inputs you send. You must NOT copy, paraphrase, translate,
  'clean up', or reformat his message into the tool's `title` field. The
  `title` should be a SHORT tag (<80 chars) you invent to help sort the
  dev queue — like a ticket label. Do NOT put the full bug report inside
  `title`. Do NOT include a `description` field — it no longer exists.
  Just set `title` (short label), `severity` (low/medium/high), and
  `screen` (widget/chat/board/drafts/goals/etc if mentioned).
  Confirm in one line: "Logged bug — <title>. Will fix next session."

RESPONSE RULES:
- Never use markdown: no **bold**, no - bullets, no [N] IDs
- Never show internal data formats to user
- Hindi input → reply in Hindi
- English input → reply in English
- Mixed → match their mix naturally
- Confirm actions in 1 sentence: "Added — Call vendor, tomorrow 3pm."
- Never say "Is there anything else?" robotically after every response

VOICE RESPONSE RULES (when input_type == voice):
- Maximum 2 sentences
- Conversational, no lists
- Natural spoken language

DATA RULES:
- Never invent tasks or data not in context
- Never reference other user's data
- Current user: ${user.name} only

CURRENT DATA CONTEXT:
Recent tasks:
${formatTasks(recentTasks)}

Recent thoughts:
${formatThoughts(recentThoughts)}
''';
  }

  // Build tools array based on user
  List<Map<String, dynamic>> _buildTools(String userId) {
    final tools = [
      {
        'name': 'create_task',
        'description': 'Create a new task. Use when user mentions something to do.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'category': {
              'type': 'string',
              'enum': AppConstants.taskCategories,
            },
            'due_date': {'type': 'string', 'nullable': true},
            'due_time': {'type': 'string', 'nullable': true},
            'priority': {
              'type': 'string',
              'enum': AppConstants.priorityLevels,
            },
            'notes': {'type': 'string'},
          },
          'required': ['title', 'category'],
        },
      },
      {
        'name': 'create_recurring_task',
        'description': 'Create a recurring habit or reminder.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'category': {'type': 'string'},
            'frequency': {
              'type': 'string',
              'enum': AppConstants.recurringFrequencies,
            },
            'frequency_details': {'type': 'string'},
            'time_of_day': {'type': 'string', 'nullable': true},
            'start_date': {'type': 'string'},
            'priority': {
              'type': 'string',
              'enum': AppConstants.priorityLevels,
            },
          },
          'required': ['title', 'category', 'frequency', 'start_date'],
        },
      },
      {
        'name': 'update_task',
        'input_schema': {
          'type': 'object',
          'properties': {
            'task_id': {'type': 'string'},
            'fields': {'type': 'object'},
          },
          'required': ['task_id', 'fields'],
        },
      },
      {
        'name': 'delete_task',
        'input_schema': {
          'type': 'object',
          'properties': {
            'task_id': {'type': 'string'},
          },
          'required': ['task_id'],
        },
      },
      {
        'name': 'mark_task_done',
        'input_schema': {
          'type': 'object',
          'properties': {
            'task_id': {'type': 'string'},
          },
          'required': ['task_id'],
        },
      },
      {
        'name': 'save_thought',
        'description': 'Save a note, idea, or thought.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'content': {'type': 'string'},
            'category': {
              'type': 'string',
              'enum': AppConstants.thoughtCategories,
            },
          },
          'required': ['title', 'content'],
        },
      },
      {
        'name': 'save_goal',
        'input_schema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'description': {'type': 'string'},
            'deadline': {'type': 'string', 'nullable': true},
            'status': {
              'type': 'string',
              'enum': AppConstants.goalStatuses,
            },
          },
          'required': ['title'],
        },
      },
      {
        'name': 'set_reminder',
        'input_schema': {
          'type': 'object',
          'properties': {
            'message': {'type': 'string'},
            'remind_at': {'type': 'string'},
            'task_id': {'type': 'string', 'nullable': true},
          },
          'required': ['message', 'remind_at'],
        },
      },
      {
        'name': 'show_board',
        'description': "Show the user's current board/tasks",
        'input_schema': {
          'type': 'object',
          'properties': {},
        },
      },
      {
        'name': 'search_data',
        'input_schema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'collections': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['tasks', 'thoughts', 'goals', 'finance', 'meals'],
              },
            },
          },
          'required': ['query'],
        },
      },
      {
        'name': 'report_bug',
        'description':
            "Log a bug, issue, or feature request for the Jarvis app itself. "
            "Use when user says 'bug:', 'fix:', 'broken', 'not working', "
            "'can you make', or describes a problem with the app. "
            "IMPORTANT: Pallav's EXACT words are captured automatically by "
            "the app outside this tool. Your only job here is to tag the bug "
            "with a short title + severity + screen so the dev queue can be "
            "sorted. DO NOT rewrite, translate, summarise, or 'clean up' the "
            "user's text — that's captured verbatim elsewhere.",
        'input_schema': {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description':
                  'Short tag/label for the bug (under 80 chars) so the dev '
                  "queue can show a one-liner. This IS a summary, it's fine to "
                  'paraphrase here. Example: "Draft button spins forever >5MB".',
            },
            'severity': {
              'type': 'string',
              'enum': ['low', 'medium', 'high'],
              'description':
                  'low = cosmetic/minor, medium = annoying but not blocking, '
                  'high = blocks core flow or loses data.',
            },
            'screen': {
              'type': 'string',
              'description':
                  'Which screen/feature is affected if mentioned '
                  '(e.g. "board", "chat", "widget", "drafts", "goals").',
            },
          },
          'required': ['title'],
        },
      },
    ];

    // Finance tool — available to both Pallav and Rakhi. Each user's
    // entries live under their own users/{uid}/finance subtree, so data
    // is fully separated. Previously Pallav-only; ungated 2026-04-23
    // per Rakhi's request.
    if (userId == AppConstants.pallavUserId ||
        userId == AppConstants.rakhiUserId) {
      tools.insert(6, {
        'name': 'save_finance',
        'input_schema': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'value': {'type': 'number'},
            'category': {
              'type': 'string',
              'enum': AppConstants.financeCategories,
            },
            'notes': {'type': 'string'},
          },
          'required': ['title'],
        },
      });
    }

    // Add time-logging tool for Pallav only.
    // Covers "log 2h client meeting", "I spent 30 min on emails", "visited
    // Rajiv at Shriram for 1.5 hours to discuss VRF quote". The tool also
    // handles visit logs (kind='visit') with extra contact/discussion
    // fields so Pallav can track architect/consultant/builder meetings.
    if (userId == AppConstants.pallavUserId) {
      tools.add({
        'name': 'log_time',
        'description':
            "Log how much time Pallav spent on an activity today (or on a "
            "specified date). Use when user says 'log 2 hours on X', "
            "'I spent 30 min doing Y', 'worked on proposal for 1.5h', "
            "'visited <person> at <company>', 'had a call with Z'. "
            "Writes a structured TimeLog to Firestore users/{id}/time_logs. "
            "Set kind='visit' when it's a client/consultant/architect/builder "
            "meeting (needs the visit_* fields). Otherwise kind='routine'.",
        'input_schema': {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['routine', 'visit'],
              'description':
                  "'visit' for client/consultant/architect/builder meetings. "
                  "'routine' for everything else (emails, admin, planning, "
                  "calls, travel, learning).",
            },
            'duration_min': {
              'type': 'integer',
              'description':
                  "Duration in minutes. 1h = 60, 1.5h = 90. Convert any "
                  "hours/decimal the user gives to integer minutes.",
            },
            'category_id': {
              'type': 'string',
              'enum': [
                'client_meeting',
                'calls',
                'quotation',
                'team_mgmt',
                'strategy',
                'email',
                'travel',
                'mis',
                'admin',
                'learning',
              ],
              'description':
                  "Best-fit category. client_meeting = meeting with a "
                  "customer/architect/consultant/builder. calls = phone/video "
                  "calls. quotation = writing proposals / BOQs. team_mgmt = "
                  "managing team / reviews. strategy = planning, thinking. "
                  "email = email + WhatsApp work. travel = commute, site trip. "
                  "mis = reports/dashboards. admin = misc office work. "
                  "learning = reading, courses, upskilling.",
            },
            'activity': {
              'type': 'string',
              'description':
                  "Short label (under 80 chars) for what was done. E.g. "
                  "'VRF proposal for Shriram', 'reviewing inbox', 'team "
                  "standup'.",
            },
            'date': {
              'type': 'string',
              'description':
                  "ISO date YYYY-MM-DD. Default to today if not mentioned.",
            },
            'is_revenue': {
              'type': 'boolean',
              'description':
                  "Whether this counts as revenue-generating. Defaults to "
                  "the category's default but user can override (e.g. 'log "
                  "30 min emails with Rajiv — count as revenue' because it "
                  "was actually about a live deal).",
            },
            'notes': {'type': 'string'},
            'client_name': {
              'type': 'string',
              'description': "Name of the client/person if mentioned.",
            },
            'visit_contact_type': {
              'type': 'string',
              'enum': ['customer', 'consultant', 'architect', 'builder',
                       'contractor', 'dealer', 'internal'],
              'description':
                  "Only for kind='visit'. Who Pallav met.",
            },
            'visit_person_name': {'type': 'string'},
            'visit_company': {'type': 'string'},
            'visit_location': {'type': 'string'},
            'visit_discussion': {
              'type': 'string',
              'description':
                  "What was discussed in the visit. Longer form than "
                  "'activity'.",
            },
            'visit_next_steps': {'type': 'string'},
          },
          'required': ['duration_min', 'category_id', 'activity'],
        },
      });
      tools.add({
        'name': 'query_emails',
        'description': 'Check emails received in the inbox. Shows importance, summary, and tasks created. Use when user asks about emails, inbox, or mail from a date range.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'days_back': {
              'type': 'integer',
              'description': '1=today only, 2=yesterday+today, 3=last 3 days, etc.',
            },
            'filter': {
              'type': 'string',
              'enum': ['all', 'critical', 'actionable', 'pending_triage'],
              'description': 'all=all processed, critical/actionable=by importance, pending_triage=not yet triaged',
            },
          },
          'required': ['days_back'],
        },
      });
    }

    // Add meal tool for Rakhi only
    if (userId == AppConstants.rakhiUserId) {
      tools.insert(7, {
        'name': 'save_meal',
        'input_schema': {
          'type': 'object',
          'properties': {
            'week_start': {'type': 'string'},
            'day_of_week': {
              'type': 'string',
              'enum': AppConstants.daysOfWeek,
            },
            'meal_type': {
              'type': 'string',
              'enum': AppConstants.mealTypes,
            },
            'description': {'type': 'string'},
          },
          'required': ['description'],
        },
      });
    }

    return tools;
  }

  Future<ClaudeResponse> sendMessage({
    required String userId,
    required UserProfile user,
    required String userMessage,
    required String inputType, // 'text' | 'voice'
    required List<Map<String, dynamic>> recentTasks,
    required List<Map<String, dynamic>> recentThoughts,
    List<Map<String, dynamic>> recentChats = const [],
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Claude API key not configured');
    }

    final systemPrompt = _buildSystemPrompt(
      user: user,
      recentTasks: recentTasks,
      recentThoughts: recentThoughts,
      inputType: inputType,
    );

    final tools = _buildTools(userId);

    // Build messages: prior turns first (oldest-first), then current user message.
    final messages = <Map<String, dynamic>>[];
    for (final chat in recentChats) {
      final role = chat['role']?.toString();
      final content = chat['content']?.toString();
      if (content == null || content.isEmpty) continue;
      // Map stored roles to Claude API roles. Only user/assistant are valid.
      if (role == 'user') {
        messages.add({'role': 'user', 'content': content});
      } else if (role == 'assistant' || role == 'tool_result') {
        messages.add({'role': 'assistant', 'content': content});
      }
    }
    // Collapse consecutive same-role turns (Claude API requires alternation).
    final collapsed = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (collapsed.isNotEmpty && collapsed.last['role'] == m['role']) {
        collapsed.last['content'] =
            '${collapsed.last['content']}\n${m['content']}';
      } else {
        collapsed.add(Map<String, dynamic>.from(m));
      }
    }
    // Ensure the last prior turn is assistant (so current user turn alternates).
    if (collapsed.isNotEmpty && collapsed.last['role'] == 'user') {
      collapsed.removeLast();
    }
    collapsed.add({'role': 'user', 'content': userMessage});

    final requestBody = {
      'model': _model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'tools': tools,
      'messages': collapsed,
    };

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return ClaudeResponse.fromJson(responseData);
      } else {
        throw Exception(
          'Claude API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to call Claude API: $e');
    }
  }

  Future<String> sendImageMessage({
    required String userId,
    required UserProfile user,
    required String imagePath,
    required List<Map<String, dynamic>> recentTasks,
    required List<Map<String, dynamic>> recentThoughts,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Claude API key not configured');
    }

    final systemPrompt = _buildSystemPrompt(
      user: user,
      recentTasks: recentTasks,
      recentThoughts: recentThoughts,
      inputType: 'text',
    );

    final imageBytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final ext = imagePath.split('.').last.toLowerCase();
    final mediaType = ext == 'png'
        ? 'image/png'
        : ext == 'gif'
            ? 'image/gif'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg';

    final requestBody = {
      'model': _model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mediaType,
                'data': base64Image,
              },
            },
            {
              'type': 'text',
              'text':
                  'What do you see in this image? Help me capture any tasks, notes, or information.',
            },
          ],
        }
      ],
    };

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final content = responseData['content'] as List<dynamic>;
        if (content.isNotEmpty && content[0]['type'] == 'text') {
          return content[0]['text'] as String;
        }
        throw Exception('No text response from Claude');
      } else {
        throw Exception(
          'Claude API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to call Claude API: $e');
    }
  }
}