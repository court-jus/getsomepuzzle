import 'package:getsomepuzzle/getsomepuzzle/model/autopilot_state.dart';

/// Stub driver for platforms that support neither isolates nor browser APIs.
class AutopilotDriver {
  /// Returns an empty list. No file is read.
  Future<List<AutopilotAction>> compute(String scenarioPath) async {
    return [];
  }

  void dispose() {}
}
