import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart' as audio_players;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Voice capture + playback.
///
/// Android uses flutter_sound + a path_provider temp-dir round-trip
/// (Codec.aacMP4 → file on disk → POST to Whisper). Byte-identical to
/// pre-web behaviour.
///
/// Web (Rakhi's PWA) uses flutter_sound_web under the hood, which wraps
/// the browser MediaRecorder API. `toFile:` on web is interpreted as a
/// blob-URL name — after stopRecorder() it returns a `blob:…` URL we
/// fetch via http.get to pull the recorded bytes out. Those bytes go
/// straight to the aiTranscribe Function; no provider key in the browser.
class AudioService {
  // Recording
  FlutterSoundRecorder? _recorder;
  bool isRecording = false;
  String? _currentRecordingPath;
  Uint8List? _webLastRecordingBytes;

  // Playback
  final audio_players.AudioPlayer _player = audio_players.AudioPlayer();
  bool isPlaying = false;

  // Initialization
  Future<void> initRecorder() async {
    try {
      // Microphone permission.
      // permission_handler on web doesn't actually work — the browser's
      // own permission prompt fires the first time getUserMedia is called
      // via MediaRecorder, which flutter_sound does internally. So skip
      // Permission.microphone on web; rely on the browser prompt.
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          throw Exception('Microphone permission denied');
        }
      }

      // Initialize recorder
      _recorder = FlutterSoundRecorder();

      // Open audio session
      await _recorder!.openRecorder();

      // Configure audio session for recording
      await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 10));
    } catch (e) {
      throw Exception('Failed to initialize recorder: $e');
    }
  }

  // Recording methods
  Future<void> startRecording() async {
    if (_recorder == null) {
      await initRecorder();
    }

    // If a recording is already in progress (e.g. previous session
    // didn't clean up properly, or a double-tap on the mic), stop it
    // first so the fresh startRecorder call doesn't throw "Instance of
    // recorder running". Tolerate stop failures — we just want a clean
    // slate before the new recording.
    if (isRecording) {
      try {
        await _recorder!.stopRecorder();
      } catch (_) {/* ignore */}
      isRecording = false;
    }

    final codec = kIsWeb ? Codec.opusWebM : Codec.aacMP4;
    final toFile = await _computeRecordingTarget();

    try {
      await _recorder!.startRecorder(toFile: toFile, codec: codec);
      _currentRecordingPath = toFile;
      isRecording = true;
    } catch (e) {
      // If flutter_sound reports an already-running recorder despite
      // the stop above (can happen on some devices when the session
      // got wedged), close and reopen the recorder fully and retry once.
      final msg = e.toString();
      if (msg.contains('recorder running') || msg.contains('already')) {
        try {
          await _recorder!.closeRecorder();
        } catch (_) {/* ignore */}
        _recorder = null;
        await initRecorder();
        final retryTarget = await _computeRecordingTarget();
        await _recorder!.startRecorder(toFile: retryTarget, codec: codec);
        _currentRecordingPath = retryTarget;
        isRecording = true;
        return;
      }
      throw Exception('Failed to start recording: $e');
    }
  }

  /// Build the `toFile:` value for startRecorder. On Android this is a
  /// real path under getTemporaryDirectory(); on web it's just a name
  /// flutter_sound_web uses as the blob-URL handle — no filesystem.
  Future<String> _computeRecordingTarget() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) {
      return 'jarvis_voice_$timestamp.webm';
    }
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/jarvis_voice_$timestamp.m4a';
  }

  /// Stop recording and return a handle for downstream transcription.
  ///
  /// Android: returns the file path (as before — chat_provider's
  /// sendVoiceMessage reads the file and POSTs it to Whisper).
  ///
  /// Web: returns the blob URL flutter_sound produced. The caller
  /// (chat_provider on web) fetches those bytes via [fetchLastRecordedBytes]
  /// and hands them to openai_service.transcribeAudioBytes which routes
  /// through the aiTranscribe proxy. We also cache the bytes in
  /// [_webLastRecordingBytes] so repeated access doesn't hit the blob
  /// URL twice.
  Future<String?> stopRecording() async {
    if (_recorder == null || !isRecording) {
      return null;
    }

    try {
      final stopResult = await _recorder!.stopRecorder();
      isRecording = false;
      if (kIsWeb) {
        // On web, stopRecorder returns the blob URL (string). Fetch
        // immediately so the caller doesn't need to worry about URL
        // lifetime / object revocation timing.
        final blobUrl = stopResult ?? _currentRecordingPath;
        _webLastRecordingBytes = null;
        if (blobUrl != null && blobUrl.isNotEmpty) {
          try {
            final resp = await http.get(Uri.parse(blobUrl));
            if (resp.statusCode == 200) {
              _webLastRecordingBytes = resp.bodyBytes;
            }
          } catch (e) {
            // ignore: avoid_print
            print('DEBUG Web blob fetch failed: $e');
          }
        }
        final path = blobUrl;
        _currentRecordingPath = null;
        return path;
      }
      final path = _currentRecordingPath;
      _currentRecordingPath = null;
      return path;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

  /// Web-only: returns the bytes of the most recent recording. Null on
  /// native (where a file path is used instead) and null if the blob
  /// fetch in stopRecording() failed.
  Uint8List? get lastRecordedBytes => _webLastRecordingBytes;

  Future<void> disposeRecorder() async {
    try {
      if (_recorder != null) {
        if (isRecording) {
          await stopRecording();
        }
        await _recorder!.closeRecorder();
        _recorder = null;
      }
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  // Playback methods
  Future<void> playFromBytes(Uint8List audioBytes) async {
    try {
      if (kIsWeb) {
        // Browser: no filesystem — feed the mp3 bytes directly to
        // audioplayers via BytesSource. Same route TTS playback takes
        // on web now that the aiTTS proxy is live.
        _player.onPlayerStateChanged.listen((state) {
          if (state == audio_players.PlayerState.completed) {
            isPlaying = false;
          }
        });
        await _player.play(audio_players.BytesSource(audioBytes));
        isPlaying = true;
        return;
      }

      // Native: keep the existing temp-file path for Android — unchanged.
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempPath = '${tempDir.path}/jarvis_tts_$timestamp.mp3';

      final file = File(tempPath);
      await file.writeAsBytes(audioBytes);

      // Setup player completion listener
      _player.onPlayerStateChanged.listen((state) {
        if (state == audio_players.PlayerState.completed) {
          isPlaying = false;
        }
      });

      // Play the file
      await _player.play(audio_players.DeviceFileSource(tempPath));
      isPlaying = true;
    } catch (e) {
      throw Exception('Failed to play audio: $e');
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
      isPlaying = false;
    } catch (e) {
      throw Exception('Failed to stop playback: $e');
    }
  }

  Future<void> disposePlayer() async {
    try {
      await _player.dispose();
    } catch (e) {
      // Ignore errors during disposal
    }
  }

  // Cleanup
  Future<void> dispose() async {
    await disposeRecorder();
    await disposePlayer();
  }
}
