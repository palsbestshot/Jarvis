// Public entry point for web-only permission prompts. Uses conditional
// imports: on native (dart:io present), we load the stub that returns
// false; on web (dart:html present), we load the real implementation.
//
// Callers that live in shared code can import this file without caring
// about the platform — the linker picks the right implementation.

export 'web_permissions_stub.dart'
    if (dart.library.html) 'web_permissions_web.dart';
