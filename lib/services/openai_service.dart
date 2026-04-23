import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Wraps OpenAI Whisper (speech → text) and TTS (text → speech).
///
/// On Android we hit api.openai.com directly with the bundled key — byte-
/// for-byte the same flow Pallav has used since day one. On Flutter Web
/// we route through our `aiTranscribe` and `aiTTS` Firebase Functions so
/// the OPENAI_API_KEY never touches the browser bundle; auth is the
/// X-Ingest-Secret header compiled in from env.web.json.
class OpenAIService {
  final String _apiKey = AppConstants.openaiApiKey;

  // ── Whisper (speech → text) ─────────────────────────────────────────

  /// Native path — reads a file from disk, POSTs multipart to Whisper.
  /// Unused on Web (no filesystem); use [transcribeAudioBytes] instead.
  Future<String> transcribeAudio(String filePath) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'transcribeAudio(path) is native-only. Use transcribeAudioBytes on web.',
      );
    }

    if (_apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    try {
      final uri = Uri.parse('${AppConstants.openaiApiUrl}/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.fields['model'] = AppConstants.whisperModel;
      request.fields['language'] = 'en';
      request.fields['response_format'] = 'text';

      final file = await http.MultipartFile.fromPath('file', filePath);
      request.files.add(file);

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return responseBody.trim();
      } else {
        final errorData = jsonDecode(responseBody);
        final errorMessage =
            errorData['error']?['message'] ?? 'Transcription failed';
        throw Exception('Whisper API error: $errorMessage');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  /// Platform-agnostic — takes raw bytes (e.g. from MediaRecorder on web
  /// or from a file read on native) and transcribes via our proxy on
  /// web, or directly via OpenAI on native. Call this everywhere and
  /// you don't have to worry about paths.
  Future<String> transcribeAudioBytes(
    Uint8List audioBytes, {
    String mimeType = 'audio/webm',
    String language = 'en',
  }) async {
    if (kIsWeb) {
      if (AppConstants.ingestSecret.isEmpty) {
        throw Exception(
          'Ingest secret not configured (set INGEST_SECRET in env.web.json)',
        );
      }
      final resp = await http.post(
        Uri.parse(AppConstants.aiTranscribeUrl),
        headers: {
          'content-type': 'application/json',
          'x-ingest-secret': AppConstants.ingestSecret,
        },
        body: jsonEncode({
          'audioBase64': base64Encode(audioBytes),
          'mimeType': mimeType,
          'language': language,
        }),
      );
      if (resp.statusCode != 200) {
        throw Exception('aiTranscribe proxy error: ${resp.statusCode} ${resp.body}');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return (json['transcript'] ?? '').toString().trim();
    }

    // Native path — same Whisper endpoint, just skip the path round-trip.
    if (_apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }
    final uri = Uri.parse('${AppConstants.openaiApiUrl}/audio/transcriptions');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_apiKey';
    request.fields['model'] = AppConstants.whisperModel;
    request.fields['language'] = language;
    request.fields['response_format'] = 'text';
    final filename = mimeType.contains('mp4')
        ? 'voice.m4a'
        : mimeType.contains('webm')
            ? 'voice.webm'
            : 'voice.mp3';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: filename,
    ));
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    if (response.statusCode == 200) {
      return responseBody.trim();
    }
    final errorData = jsonDecode(responseBody);
    final errorMessage =
        errorData['error']?['message'] ?? 'Transcription failed';
    throw Exception('Whisper API error: $errorMessage');
  }

  // ── TTS (text → speech) ─────────────────────────────────────────────

  Future<Uint8List> generateSpeech(String text, String voice) async {
    if (kIsWeb) {
      if (AppConstants.ingestSecret.isEmpty) {
        throw Exception(
          'Ingest secret not configured (set INGEST_SECRET in env.web.json)',
        );
      }
      final resp = await http.post(
        Uri.parse(AppConstants.aiTtsUrl),
        headers: {
          'content-type': 'application/json',
          'x-ingest-secret': AppConstants.ingestSecret,
        },
        body: jsonEncode({'text': text, 'voice': voice}),
      );
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      }
      throw Exception('aiTTS proxy error: ${resp.statusCode} ${resp.body}');
    }

    // Native — unchanged from original implementation.
    if (_apiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }
    try {
      final uri = Uri.parse('${AppConstants.openaiApiUrl}/audio/speech');
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };
      final body = jsonEncode({
        'model': AppConstants.ttsModel,
        'input': text,
        'voice': voice,
        'response_format': 'mp3',
      });
      final response = await http.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      final errorData = jsonDecode(response.body);
      final errorMessage =
          errorData['error']?['message'] ?? 'TTS generation failed';
      throw Exception('TTS API error: $errorMessage');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to generate speech: $e');
    }
  }
}
