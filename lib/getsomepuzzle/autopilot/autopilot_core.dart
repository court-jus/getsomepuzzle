import 'package:getsomepuzzle/getsomepuzzle/model/autopilot_state.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:logging/logging.dart';

final _log = Logger('parseScenario');

/// Parse a scenario file [content] into a list of actions.
///
/// Lines starting with `#` (after trimming) are comments. Empty lines are
/// ignored. Every other line must be an action. Malformed actions produce a
/// warning via [Logger] and are omitted from the result — the scenario
/// continues with the next line.
List<AutopilotAction> parseScenario(String content) {
  final actions = <AutopilotAction>[];
  final lines = content.split('\n');
  for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
    var line = lines[lineIdx];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final parts = _tokenise(trimmed);
    if (parts.isEmpty) continue;

    final keyword = parts[0].toLowerCase();
    final args = parts.sublist(1);

    try {
      switch (keyword) {
        case 'loadstate':
          if (args.isEmpty) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: loadState needs a v2 line',
            );
            continue;
          }
          // The v2 line may contain underscores; join everything back.
          final v2Line = args.join('_');
          actions.add(LoadStateAction(v2Line));

        case 'wait':
          if (args.isEmpty) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: wait needs a duration in ms',
            );
            continue;
          }
          final ms = int.tryParse(args[0]);
          if (ms == null || ms < 0) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: invalid wait duration "${args[0]}"',
            );
            continue;
          }
          actions.add(WaitAction(ms));

        case 'mouse':
          if (args.isEmpty) {
            _log.warning('autopilot line ${lineIdx + 1}: mouse needs col,row');
            continue;
          }
          final (col, row) = _parseCoords(args[0], lineIdx);
          if (col == null || row == null) continue;
          actions.add(MouseAction(col, row));

        case 'mouseto':
          if (args.isEmpty || args[0].isEmpty) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: mouseTo needs a target',
            );
            continue;
          }
          actions.add(MouseToAction(args[0]));

        case 'setvalue':
          if (args.isEmpty) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: setValue needs col,row,color',
            );
            continue;
          }
          // The format is one token: "col,row,color".
          final setParts = args[0].split(',');
          if (setParts.length != 3) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: expected col,row,color got '
              '"${args[0]}"',
            );
            continue;
          }
          final col = int.tryParse(setParts[0]);
          final row = int.tryParse(setParts[1]);
          if (col == null || row == null) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: non-numeric coordinate '
              '"${setParts[0]},${setParts[1]}"',
            );
            continue;
          }
          final value = _parseColor(setParts[2], lineIdx);
          if (value == null) continue;
          actions.add(SetValueAction(col, row, value));

        case 'dialog':
          // `dialog` alone → close-all signal.
          // `dialog "title" "text"` → show dialog.
          // `dialog "" "text"` → empty title.
          actions.add(
            args.isEmpty
                ? const DialogAction()
                : DialogAction(
                    title: args[0],
                    text: args.length > 1 ? args[1] : '',
                  ),
          );

        case 'textcolor':
          if (args.length < 3) {
            _log.warning(
              'autopilot line ${lineIdx + 1}: '
              'textcolor needs exactly three colors: textColor fillColor '
              'borderColor',
            );
            continue;
          }
          actions.add(
            TextColorAction(
              textColor: args[0],
              fillColor: args[1],
              borderColor: args[2],
            ),
          );

        case 'hint':
          actions.add(const HintAction());

        default:
          _log.warning(
            'autopilot line ${lineIdx + 1}: unknown action "$keyword"',
          );
      }
    } catch (e) {
      _log.warning('autopilot line ${lineIdx + 1}: error: $e');
    }
  }
  return actions;
}

/// Tokenise [line] into parts: unquoted tokens are split on whitespace,
/// double-quoted strings (`"..."`) become single tokens including whitespace
/// and `\n` escape sequences (which are converted to actual newlines).
List<String> _tokenise(String line) {
  final result = <String>[];
  int i = 0;
  while (i < line.length) {
    if (line[i] == ' ') {
      i++;
      continue;
    }
    if (line[i] == '"') {
      // Quoted string — find the closing quote.
      final close = line.indexOf('"', i + 1);
      if (close < 0) {
        // Unterminated quote — treat the rest as a single token.
        result.add(line.substring(i + 1));
        break;
      }
      var raw = line.substring(i + 1, close);
      // Convert \n escape sequences to actual newlines.
      raw = raw.replaceAll('\\n', '\n');
      result.add(raw);
      i = close + 1;
    } else {
      // Unquoted token — read until next whitespace.
      final end = line.indexOf(' ', i);
      if (end < 0) {
        result.add(line.substring(i));
        break;
      }
      result.add(line.substring(i, end));
      i = end + 1;
    }
  }
  return result.where((s) => s.isNotEmpty).toList();
}

/// Parse "col,row" from [token]. Returns null on failure.
(int? col, int? row) _parseCoords(String token, int lineIdx) {
  final coordParts = token.split(',');
  if (coordParts.length != 2) {
    _log.warning(
      'autopilot line ${lineIdx + 1}: expected col,row got "$token"',
    );
    return (null, null);
  }
  final col = int.tryParse(coordParts[0]);
  final row = int.tryParse(coordParts[1]);
  if (col == null || row == null) {
    _log.warning(
      'autopilot line ${lineIdx + 1}: non-numeric coordinate "$token"',
    );
    return (null, null);
  }
  return (col, row);
}

/// Parse a colour name into a [CellValue]. Case-insensitive.
CellValue? _parseColor(String name, int lineIdx) {
  switch (name.toLowerCase()) {
    case 'free':
      return CellValue.free;
    case 'black':
      return CellValue.black;
    case 'white':
      return CellValue.white;
    case 'purple':
      return CellValue.purple;
    default:
      _log.warning(
        'autopilot line ${lineIdx + 1}: unknown colour "$name" '
        '(expected free, black, white, purple)',
      );
      return null;
  }
}
