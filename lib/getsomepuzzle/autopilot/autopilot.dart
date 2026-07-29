// Conditional exports: native uses Isolate.spawn, web uses main-thread
// reading, other platforms get a stub.
export 'autopilot_stub.dart'
    if (dart.library.io) 'autopilot_io.dart'
    if (dart.library.html) 'autopilot_web.dart';
