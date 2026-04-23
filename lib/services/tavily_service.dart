import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

// Tavily search result model
class TavilyResult {
  final String? directAnswer;
  final List<TavilySearchResult> results;

  TavilyResult({
    this.directAnswer,
    required this.results,
  });

  factory TavilyResult.fromJson(Map<String, dynamic> json) {
    final resultsJson = json['results'] as List? ?? [];
    final results = resultsJson
        .map((resultJson) => TavilySearchResult.fromJson(resultJson))
        .toList();

    return TavilyResult(
      directAnswer: json['answer'],
      results: results,
    );
  }
}

// Individual search result model
class TavilySearchResult {
  final String title;
  final String url;
  final String content;
  final double score;

  TavilySearchResult({
    required this.title,
    required this.url,
    required this.content,
    required this.score,
  });

  factory TavilySearchResult.fromJson(Map<String, dynamic> json) {
    return TavilySearchResult(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      content: json['content'] ?? '',
      score: (json['score'] ?? 0.0).toDouble(),
    );
  }
}

class TavilyService {
  static const String _apiUrl = 'https://api.tavily.com/search';

  Future<TavilyResult> search(String query, {int numResults = 5}) async {
    try {
      final apiKey = AppConstants.tavilyApiKey;
      
      if (apiKey.isEmpty) {
        throw Exception('Tavily API key not configured. Add to env.json');
      }

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'api_key': apiKey,
          'query': query,
          'search_depth': 'basic',
          'max_results': numResults,
          'include_answer': true,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Tavily API error: ${response.statusCode} - ${response.body}');
      }

      final responseData = jsonDecode(response.body);
      return TavilyResult.fromJson(responseData);
    } catch (e) {
      rethrow;
    }
  }

  // Helper method to format search results as readable text
  String formatResults(TavilyResult result) {
    final buffer = StringBuffer();
    
    if (result.directAnswer != null && result.directAnswer!.isNotEmpty) {
      buffer.write('Answer: ${result.directAnswer}\n\n');
    }
    
    if (result.results.isNotEmpty) {
      buffer.write('Sources:\n');
      
      for (var i = 0; i < result.results.length; i++) {
        final resultItem = result.results[i];
        buffer.write('${i + 1}. ${resultItem.title} — ${resultItem.url}\n');
        
        // Include a brief snippet of content
        if (resultItem.content.isNotEmpty) {
          final snippet = resultItem.content.length > 150 
              ? '${resultItem.content.substring(0, 150)}...'
              : resultItem.content;
          buffer.write('   $snippet\n');
        }
        
        buffer.write('\n');
      }
    }
    
    return buffer.toString();
  }
}