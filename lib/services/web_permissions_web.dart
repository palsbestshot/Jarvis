// Web-only mic + camera permission prompts. Called from the first-
// launch onboarding screen so Rakhi grants everything up front and
// later features (voice chat, photo send) don't trap her mid-flow.
//
// Uses dart:html.getUserMedia — the same Web API Safari / Chrome use
// natively for mic + camera. We request a stream, immediately stop it,
// and return true if the browser granted the request. iOS Safari only
// honors these in response to a user gesture (button tap), which is
// exactly how this file is invoked.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Ask the browser for mic access. Returns true iff the user granted it.
Future<bool> requestMicrophoneWeb() async {
  try {
    final stream = await html.window.navigator.mediaDevices!
        .getUserMedia({'audio': true});
    // Release the track immediately — we just wanted the permission
    // grant; actual recording happens later via flutter_sound.
    for (final track in stream.getTracks()) {
      track.stop();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Ask the browser for camera access. Returns true iff granted. Like
/// mic, we stop the stream immediately — photo capture happens later
/// via image_picker.
Future<bool> requestCameraWeb() async {
  try {
    final stream = await html.window.navigator.mediaDevices!
        .getUserMedia({'video': true});
    for (final track in stream.getTracks()) {
      track.stop();
    }
    return true;
  } catch (_) {
    return false;
  }
}
