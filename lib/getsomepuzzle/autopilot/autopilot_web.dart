import 'package:getsomepuzzle/getsomepuzzle/model/autopilot_state.dart';
import 'package:logging/logging.dart';

final _log = Logger('AutopilotDriver');

/// Web autopilot driver — always returns an empty list because there is no
/// CLI flag to pass a scenario path on the web. The autopilot mode is a
/// desktop-only feature.
///
/// The public interface matches the native isolate driver so the caller
/// (main.dart) can use it uniformly regardless of platform.
class AutopilotDriver {
  Future<List<AutopilotAction>> compute(String scenarioPath) async {
    _log.warning('autopilot: web does not support --scenario="$scenarioPath"');
    return [];
  }

  void dispose() {}
}
