import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart' as audio_players;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  // Recording
  FlutterSoundRecorder? _recorder;
  bool isRecording = false;
  String? _currentRecordingPath;

  // Playback
  final audio_players.AudioPlayer _player = audio_players.AudioPlayer();
  bool isPlaying = false;

  // Initialization
  Future<void> initRecorder() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        throw Exception('Microphone permission denied');
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

    try {
      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/jarvis_voice_$timestamp.m4a';

      // Start recording
      await _recorder!.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacMP4,
      );

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
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _currentRecordingPath = '${tempDir.path}/jarvis_voice_$timestamp.m4a';
        await _recorder!.startRecorder(
          toFile: _currentRecordingPath,
          codec: Codec.aacMP4,
        );
        isRecording = true;
        return;
      }
      throw Exception('Failed to start recording: $e');
    }
  }

  Future<String?> stopRecording() async {
    if (_recorder == null || !isRecording) {
      return null;
    }

    try {
      await _recorder!.stopRecorder();
      isRecording = false;
      final path = _currentRecordingPath;
      _currentRecordingPath = null;
      return path;
    } catch (e) {
      throw Exception('Failed to stop recording: $e');
    }
  }

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
      // Write bytes to temp file
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