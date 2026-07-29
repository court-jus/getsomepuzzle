import 'dart:io';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/autopilot/autopilot_core.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/autopilot_state.dart';
import 'package:logging/logging.dart';

final _log = Logger('AutopilotDriver');

/// Native isolate-based autopilot driver.
///
/// Spawns an isolate that reads the scenario file from disk, parses it, and
/// sends the complete action list back via [SendPort].
class AutopilotDriver {
  Isolate? _isolate;
  ReceivePort? _receivePort;

  /// Read and parse the scenario file at [scenarioPath].
  ///
  /// Returns the parsed actions, or an empty list on failure.
  Future<List<AutopilotAction>> compute(String scenarioPath) async {
    final port = ReceivePort();
    _receivePort = port;

    try {
      _isolate = await Isolate.spawn(
        _isolateEntryPoint,
        _ScenarioParams(sendPort: port.sendPort, filePath: scenarioPath),
      );

      final result = await port.first;
      final list = result as List<Object?>;

      // Deserialise: the isolate sends raw Maps/Lists since SendPort
      // only accepts primitive-like types.
      final actions = list.map((e) => e as AutopilotAction).toList();

      return actions;
    } catch (e) {
      _log.warning('autopilot: failed to read scenario "$scenarioPath": $e');
      return [];
    } finally {
      port.close();
      if (identical(_receivePort, port)) {
        _receivePort = null;
      }
      _isolate = null;
    }
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
  }
}

/// Parameters sent to the isolate.
class _ScenarioParams {
  final SendPort sendPort;
  final String filePath;

  const _ScenarioParams({required this.sendPort, required this.filePath});
}

/// Entry point running in the spawned isolate.
Future<void> _isolateEntryPoint(_ScenarioParams params) async {
  try {
    final file = File(params.filePath);
    final content = await file.readAsString();
    final actions = parseScenario(content);
    params.sendPort.send(actions);
  } catch (e) {
    _log.warning('autopilot isolate: error reading "$params.filePath": $e');
    params.sendPort.send(<AutopilotAction>[]);
  }
}
