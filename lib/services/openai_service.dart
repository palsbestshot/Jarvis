import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class OpenAIService {
  final String _apiKey = AppConstants.openaiApiKey;

  Future<String> transcribeAudio(String filePath) async {
    print('DEBUG: OpenAI key length: ${_apiKey.length}');
    if (_apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['Authorization'] = 'Bearer $_apiKey';

      // Add form fields
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      request.fields['response_format'] = 'text';

      // Add audio file
      final file = await http.MultipartFile.fromPath('file', filePath);
      request.files.add(file);

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return responseBody.trim();
      } else {
        final errorData = jsonDecode(responseBody);
        final errorMessage = errorData['error']['message'] ?? 'Transcription failed';
        throw Exception('Whisper API error: $errorMessage');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  Future<Uint8List> generateSpeech(String text, String voice) async {
    if (_apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/speech');
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'model': 'tts-1',
        'input': text,
        'voice': voice,
        'response_format': 'mp3',
      });

      final response = await http.post(uri, headers: headers, body: body);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']['message'] ?? 'TTS generation failed';
        throw Exception('TTS API error: $errorMessage');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to generate speech: $e');
    }
  }
}