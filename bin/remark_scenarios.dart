// Tag legacy v2 puzzle lines with a `scenario:<name>` suffix when a
// non-classic scenario can be inferred from the constraint list and
// the solver trace. Used once after `scenario:` became authoritative —
// see `docs/dev/collection_management.md`.
//
// Detection algorithm:
//   1. presence of `SH:` constraint → `sh` (no trace needed).
//   2. otherwise, apply two cheap topological pre-filters:
//        - PATH_TOPO: ≥ min-letters distinct LT letters AND each LT
//          letter has its anchors at Manhattan distance ≥ min-anchor-
//          distance from one another.
//        - SY_TOPO  : ≥ min-sy-seeds distinct SY anchors.
//      If neither passes → leave as classic (no marker added).
//   3. if either passes, run the solver via `solveExplained` once and
//      compute, on the propagation steps only:
//        - lt-share / sy-share = fraction of propagation steps issued
//          by an LT / SY constraint
//        - lt-interesting / sy-interesting = number of those steps
//          with complexity ≥ 2
//      Each scenario is "qualified" iff its topo pre-filter passed
//      AND its share ≥ threshold AND its interesting ≥ threshold.
//   4. Choose:
//        - both qualified → the one with the larger share (LT wins
//          ties; near-impossible in practice since the path and sy
//          generators exclude each other's dominant slug).
//        - one qualified → that one.
//        - neither       → classic (no marker added).
//
// `classic` is the implicit default for an unmarked line at read time
// (see `detectPuzzleProfile` in `equilibrium.dart`). Lines that
// already carry a `_scenario:` suffix are passed through unchanged —
// re-runs are idempotent. Comments, blank lines and non-`v2_` rows
// are passed through too.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

const List<String> _kStandardCollections = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
  'assets/overfilled-easy.txt',
  'assets/overfilled.txt',
];

class _Thresholds {
  final int minLetters;
  final int minAnchorDistance;
  final int minSySeeds;
  final double minLtShare;
  final int minLtInteresting;
  final double minSyShare;
  final int minSyInteresting;
  final int timeoutMs;

  const _Thresholds({
    required this.minLetters,
    required this.minAnchorDistance,
    required this.minSySeeds,
    required this.minLtShare,
    required this.minLtInteresting,
    required this.minSyShare,
    required this.minSyInteresting,
    required this.timeoutMs,
  });
}

void main(List<String> args) {
  String? outputPath;
  bool dryRun = false;
  bool verbose = false;
  int minLetters = 2;
  int minAnchorDistance = 2;
  int minSySeeds = 2;
  double minLtShare = 0.5;
  int minLtInteresting = 1;
  double minSyShare = 0.5;
  int minSyInteresting = 1;
  int timeoutMs = 15000;
  final inputs = <String>[];

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    String next() {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing argument after $a');
        exit(1);
      }
      return args[++i];
    }

    switch (a) {
      case '-o':
      case '--output':
        outputPath = next();
      case '--dry-run':
        dryRun = true;
      case '-v':
      case '--verbose':
        verbose = true;
      case '--min-letters':
        minLetters = int.parse(next());
      case '--min-anchor-distance':
        minAnchorDistance = int.parse(next());
      case '--min-sy-seeds':
        minSySeeds = int.parse(next());
      case '--min-lt-share':
        minLtShare = double.parse(next());
      case '--min-lt-interesting':
        minLtInteresting = int.parse(next());
      case '--min-sy-share':
        minSyShare = double.parse(next());
      case '--min-sy-interesting':
        minSyInteresting = int.parse(next());
      case '--timeout-ms':
        timeoutMs = int.parse(next());
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      default:
        if (a.startsWith('-')) {
          stderr.writeln('Unknown argument: $a');
          exit(1);
        }
        inputs.add(a);
    }
  }

  final List<String> effectiveInputs = inputs.isEmpty
      ? List<String>.from(_kStandardCollections)
      : inputs;

  if (effectiveInputs.length > 1 && outputPath != null) {
    stderr.writeln('--output expects a single input file');
    exit(1);
  }

  if (inputs.isEmpty) {
    stderr.writeln(
      'No input files given; processing the standard collections:',
    );
    for (final p in _kStandardCollections) {
      stderr.writeln('  - $p');
    }
  }

  final thresholds = _Thresholds(
    minLetters: minLetters,
    minAnchorDistance: minAnchorDistance,
    minSySeeds: minSySeeds,
    minLtShare: minLtShare,
    minLtInteresting: minLtInteresting,
    minSyShare: minSyShare,
    minSyInteresting: minSyInteresting,
    timeoutMs: timeoutMs,
  );

  for (final input in effectiveInputs) {
    _processFile(
      input,
      outputPath,
      thresholds: thresholds,
      dryRun: dryRun,
      verbose: verbose,
    );
  }
}

void _printUsage() {
  stderr.writeln(
    'Usage: dart run bin/remark_scenarios.dart [options] [<puzzle_file>...]\n\n'
    'If no input file is given, processes the standard collections:\n'
    '${_kStandardCollections.map((p) => '  - $p').join('\n')}\n\n'
    'Options:\n'
    '  -o, --output <file>       Write to this file (default:\n'
    '                            <input>.remarked.txt). Single input only.\n'
    '      --dry-run             Report counts; do not write output files.\n'
    '  -v, --verbose             Log each line that gets re-marked.\n\n'
    'Topological pre-filters (cheap, gate the trace step):\n'
    '      --min-letters N       ≥ N distinct LT letters (default 2).\n'
    '      --min-anchor-distance N\n'
    '                            Min Manhattan distance between any two\n'
    '                            anchors of the same LT letter (default 2).\n'
    '      --min-sy-seeds N      ≥ N distinct SY anchors (default 2).\n\n'
    'Trace thresholds (require solver execution):\n'
    '      --min-lt-share F      Fraction of propagation steps issued by\n'
    '                            an LT constraint (default 0.5).\n'
    '      --min-lt-interesting N\n'
    '                            LT propagation steps with complexity ≥ 2\n'
    '                            (default 1).\n'
    '      --min-sy-share F      Fraction of propagation steps issued by\n'
    '                            an SY constraint (default 0.5).\n'
    '      --min-sy-interesting N\n'
    '                            SY propagation steps with complexity ≥ 2\n'
    '                            (default 1).\n'
    '      --timeout-ms MS       Per-puzzle solve budget (default 15000).',
  );
}

void _processFile(
  String path,
  String? outputPath, {
  required _Thresholds thresholds,
  required bool dryRun,
  required bool verbose,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path (skipped)');
    return;
  }
  final lines = file.readAsLinesSync();
  final out = StringBuffer();
  int alreadyMarked = 0;
  int markedSh = 0;
  int markedSy = 0;
  int markedPath = 0;
  int classicTopo = 0;
  int classicTrace = 0;
  int traceFailed = 0;
  int skippedNonPuzzle = 0;
  final sw = Stopwatch()..start();

  for (int lineNo = 0; lineNo < lines.length; lineNo++) {
    final raw = lines[lineNo];
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      out.writeln(raw);
      skippedNonPuzzle++;
      continue;
    }
    if (!trimmed.startsWith('v2_')) {
      out.writeln(raw);
      skippedNonPuzzle++;
      continue;
    }

    final parts = trimmed.split('_');
    if (parts.any((p) => p.startsWith('scenario:'))) {
      out.writeln(raw);
      alreadyMarked++;
      continue;
    }
    if (parts.length < 5) {
      out.writeln(raw);
      skippedNonPuzzle++;
      continue;
    }

    final result = _inferScenario(trimmed, thresholds);
    switch (result.outcome) {
      case _Outcome.sh:
        markedSh++;
        out.writeln('${trimmed}_scenario:sh');
        if (verbose) stderr.writeln('  $path:${lineNo + 1}: → sh');
      case _Outcome.pathBased:
        markedPath++;
        out.writeln('${trimmed}_scenario:pathBased');
        if (verbose) {
          stderr.writeln(
            '  $path:${lineNo + 1}: → pathBased '
            'lt-share=${_pct(result.ltShare)} '
            'lt-interesting=${result.ltInteresting} '
            'sy-share=${_pct(result.syShare)}',
          );
        }
      case _Outcome.syBased:
        markedSy++;
        out.writeln('${trimmed}_scenario:syBased');
        if (verbose) {
          stderr.writeln(
            '  $path:${lineNo + 1}: → syBased '
            'sy-share=${_pct(result.syShare)} '
            'sy-interesting=${result.syInteresting} '
            'lt-share=${_pct(result.ltShare)}',
          );
        }
      case _Outcome.classicTopo:
        classicTopo++;
        out.writeln(raw);
      case _Outcome.classicTrace:
        classicTrace++;
        out.writeln(raw);
      case _Outcome.traceFailed:
        traceFailed++;
        out.writeln(raw);
        if (verbose) {
          // `trace_failed` means propagation + force couldn't close
          // the puzzle (i.e. it needs backtracking). Shipped puzzles
          // are filtered by `--check` against that, so any hit here
          // is anomalous and worth eyeballing — log the full v2 line.
          stderr.writeln(
            '  $path:${lineNo + 1}: trace_failed (needs backtracking)\n'
            '    $trimmed',
          );
        }
    }

    if ((lineNo + 1) % 200 == 0) {
      stderr.write(
        '\r  $path: processed ${lineNo + 1}/${lines.length} '
        '(sh=$markedSh sy=$markedSy path=$markedPath '
        'trace_failed=$traceFailed)   ',
      );
    }
  }

  final touched = markedSh + markedSy + markedPath;
  stderr.writeln('');
  stderr.writeln(
    '$path: '
    'total=${lines.length} '
    'already=$alreadyMarked '
    'sh=$markedSh sy=$markedSy path=$markedPath '
    'classic_topo=$classicTopo classic_trace=$classicTrace '
    'trace_failed=$traceFailed '
    'non-puzzle=$skippedNonPuzzle '
    'touched=$touched '
    'elapsed=${sw.elapsed.inSeconds}s',
  );

  if (dryRun) return;
  final dest = outputPath ?? '$path.remarked.txt';
  File(dest).writeAsStringSync(out.toString());
  stderr.writeln('  → wrote $dest');
}

enum _Outcome {
  sh,
  pathBased,
  syBased,
  // Both topological pre-filters rejected the puzzle; never ran the
  // solver (cheap classic).
  classicTopo,
  // A pre-filter passed but neither scenario qualified on the trace.
  classicTrace,
  // The solver couldn't close the puzzle within the timeout (or threw).
  traceFailed,
}

class _InferResult {
  final _Outcome outcome;
  final double ltShare;
  final double syShare;
  final int ltInteresting;
  final int syInteresting;

  const _InferResult(
    this.outcome, {
    this.ltShare = 0.0,
    this.syShare = 0.0,
    this.ltInteresting = 0,
    this.syInteresting = 0,
  });
}

_InferResult _inferScenario(String fullLine, _Thresholds t) {
  final topo = _parseTopology(fullLine);
  if (topo == null) return const _InferResult(_Outcome.classicTopo);
  if (topo.hasSh) return const _InferResult(_Outcome.sh);

  final pathTopo =
      topo.ltGroups.length >= t.minLetters &&
      topo.ltGroups.every(
        (lt) => _minPairwiseDistance(lt, topo.width) >= t.minAnchorDistance,
      );
  final syTopo = topo.symSeeds.length >= t.minSySeeds;
  if (!pathTopo && !syTopo) {
    return const _InferResult(_Outcome.classicTopo);
  }

  final metrics = _traceMetrics(fullLine, timeoutMs: t.timeoutMs);
  if (metrics == null) {
    return const _InferResult(_Outcome.traceFailed);
  }

  final ltShare = metrics.totalProp > 0
      ? metrics.ltProp / metrics.totalProp
      : 0.0;
  final syShare = metrics.totalProp > 0
      ? metrics.syProp / metrics.totalProp
      : 0.0;

  final ltQualified =
      pathTopo &&
      ltShare >= t.minLtShare &&
      metrics.ltInteresting >= t.minLtInteresting;
  final syQualified =
      syTopo &&
      syShare >= t.minSyShare &&
      metrics.syInteresting >= t.minSyInteresting;

  if (!ltQualified && !syQualified) {
    return _InferResult(
      _Outcome.classicTrace,
      ltShare: ltShare,
      syShare: syShare,
      ltInteresting: metrics.ltInteresting,
      syInteresting: metrics.syInteresting,
    );
  }
  if (ltQualified && !syQualified) {
    return _InferResult(
      _Outcome.pathBased,
      ltShare: ltShare,
      syShare: syShare,
      ltInteresting: metrics.ltInteresting,
      syInteresting: metrics.syInteresting,
    );
  }
  if (syQualified && !ltQualified) {
    return _InferResult(
      _Outcome.syBased,
      ltShare: ltShare,
      syShare: syShare,
      ltInteresting: metrics.ltInteresting,
      syInteresting: metrics.syInteresting,
    );
  }
  // Both qualified: pick the larger share; LT wins exact ties.
  final winner = ltShare >= syShare ? _Outcome.pathBased : _Outcome.syBased;
  return _InferResult(
    winner,
    ltShare: ltShare,
    syShare: syShare,
    ltInteresting: metrics.ltInteresting,
    syInteresting: metrics.syInteresting,
  );
}

class _Topology {
  final int width;
  final bool hasSh;
  final Set<int> symSeeds;
  final List<List<int>> ltGroups;
  _Topology(this.width, this.hasSh, this.symSeeds, this.ltGroups);
}

_Topology? _parseTopology(String line) {
  final parts = line.split('_');
  if (parts.length < 5) return null;
  final dims = parts[2].split('x');
  if (dims.length != 2) return null;
  final width = int.tryParse(dims[0]);
  if (width == null) return null;

  bool hasSh = false;
  final symSeeds = <int>{};
  final ltGroups = <List<int>>[];
  for (final entry in parts[4].split(';')) {
    if (entry.isEmpty) continue;
    if (entry.startsWith('SH:')) {
      hasSh = true;
    } else if (entry.startsWith('SY:')) {
      final body = entry.substring(3).split('.');
      if (body.isEmpty) continue;
      final seed = int.tryParse(body[0]);
      if (seed != null) symSeeds.add(seed);
    } else if (entry.startsWith('LT:')) {
      final body = entry.substring(3).split('.');
      if (body.length < 2) continue;
      final indices = <int>[];
      bool malformed = false;
      for (int i = 1; i < body.length; i++) {
        final v = int.tryParse(body[i]);
        if (v == null) {
          malformed = true;
          break;
        }
        indices.add(v);
      }
      if (!malformed && indices.isNotEmpty) ltGroups.add(indices);
    }
  }
  return _Topology(width, hasSh, symSeeds, ltGroups);
}

int _minPairwiseDistance(List<int> indices, int width) {
  if (indices.length < 2) return 1 << 30;
  int minDist = 1 << 30;
  for (int i = 0; i < indices.length; i++) {
    final xi = indices[i] % width;
    final yi = indices[i] ~/ width;
    for (int j = i + 1; j < indices.length; j++) {
      final xj = indices[j] % width;
      final yj = indices[j] ~/ width;
      final d = (xi - xj).abs() + (yi - yj).abs();
      if (d < minDist) minDist = d;
    }
  }
  return minDist;
}

class _TraceMetrics {
  final int totalProp;
  final int ltProp;
  final int syProp;
  final int ltInteresting;
  final int syInteresting;
  _TraceMetrics(
    this.totalProp,
    this.ltProp,
    this.syProp,
    this.ltInteresting,
    this.syInteresting,
  );
}

/// Runs `solveExplained` on the puzzle and aggregates LT/SY share +
/// "interesting" counts in one pass. Returns null if the puzzle needs
/// backtracking (mirrors `extract_path_like.dart:_traceMetrics`) or if
/// the constructor / solver throws.
_TraceMetrics? _traceMetrics(String line, {required int timeoutMs}) {
  try {
    final puzzle = Puzzle(line);
    final probe = puzzle.clone();
    if (!probe.solve()) return null;

    final steps = puzzle.solveExplained(timeoutMs: timeoutMs);
    int totalProp = 0;
    int ltProp = 0;
    int syProp = 0;
    int ltInteresting = 0;
    int syInteresting = 0;
    for (final step in steps) {
      if (step.method != SolveMethod.propagation) continue;
      totalProp++;
      if (step.constraint.startsWith('LT:')) {
        ltProp++;
        if (step.complexity >= 2) ltInteresting++;
      } else if (step.constraint.startsWith('SY:')) {
        syProp++;
        if (step.complexity >= 2) syInteresting++;
      }
    }
    return _TraceMetrics(
      totalProp,
      ltProp,
      syProp,
      ltInteresting,
      syInteresting,
    );
  } catch (_) {
    return null;
  }
}

String _pct(double x) => '${(100.0 * x).toStringAsFixed(0)}%';
