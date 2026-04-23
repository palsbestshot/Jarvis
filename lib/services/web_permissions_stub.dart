// Stub implementation used on non-web builds. The public entry point
// (web_permissions.dart) uses a conditional import that swaps this file
// for web_permissions_web.dart when Flutter Web compiles the bundle.
//
// Both functions return false on native so any accidental call from
// Pallav's Android path no-ops cleanly instead of throwing.

Future<bool> requestMicrophoneWeb() async => false;
Future<bool> requestCameraWeb() async => false;
