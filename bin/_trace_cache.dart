// Shared trace cache for the puzzle maintenance pipeline.
//
// The cache file (`solve_traces.tsv`) maps each puzzle to its post-sort
// solving trace so that maintenance tools (vectorize, cleanup, classify, …)
// can skip the expensive `solveExplained()` call when the trace is already
// known. `bin/recompute.dart` is the sole **writer** of the cache; all other
// tools are read-only consumers.
//
// File format (tab-separated, no header):
//   puzzle_hash\tcanonical_key\ttrace
//
//   puzzle_hash   — FNV-1a 32-bit hash (7 base-36 chars) of the string
//                   "domain_dims_prefill_sortedConstraints" from the v2 line.
//                   Changes whenever the puzzle identity or constraint set
//                   changes, invalidating the cached trace automatically.
//   canonical_key — kept for human readability / debugging only; not used
//                   for lookups.
//   trace         — semicolon-separated SolveStep encoding:
//                     type|cellIdx|val|tier|cp|fd|constraint
//                   type : S = SetValue/propagation
//                          R = RemoveOption/propagation
//                          s = SetValue/force          (lowercase = force)
//                          r = RemoveOption/force
//                   val  : CellValue integer (1=black, 2=white, 3=purple)
//                   tier : complexity 0-5
//                   cp   : isComplicity 0/1
//                   fd   : forceDepth (always 0 for SetValueStep)
//                   constraint : full SLUG:params string; empty for force
//
// The file is gitignored and is a local build artefact — delete it to force
// a full re-solve on the next `dart run bin/recompute.dart` run.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Default path for the trace cache, relative to the project root.
const kTraceCachePath = 'solve_traces.tsv';

// ──────────────────────────────────────────────────────────────────────────
// Hash
// ──────────────────────────────────────────────────────────────────────────

/// FNV-1a 32-bit hash of [s], returned as a 7-char base-36 string.
/// Used as the cache key — good enough collision resistance for 26k puzzles
/// without any external dependencies.
String _fnv32(String s) {
  int h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c & 0xFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
    if (c > 0xFF) {
      h ^= (c >> 8) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
  }
  return h.toRadixString(36).padLeft(7, '0');
}

/// Compute the trace key from a raw v2 puzzle line (already constraint-sorted).
/// Uses fields [1]=domain, [2]=dims, [3]=prefill, [4]=constraints.
String traceKeyFromLine(String line) {
  final u1 = line.indexOf('_');
  if (u1 < 0) return '';
  final u5 = _nthUnderscore(line, 5);
  if (u5 < 0) return '';
  // substring from after the first '_' (skip version) up to before field [5]
  return _fnv32(line.substring(u1 + 1, u5));
}

/// Compute the trace key from a [Puzzle] object whose constraints are already
/// sorted (post-[Puzzle.sortConstraintsByDifficulty]).
String traceKeyFromPuzzle(Puzzle puzzle) {
  final domain = puzzle.domain.map(cellValueToString).join('');
  final dims = '${puzzle.width}x${puzzle.height}';
  final prefill = puzzle.cells
      .map((c) => cellValueToString(c.readonly ? c.value : CellValue.free))
      .join('');
  final constraints = puzzle.constraints.map((c) => c.serialize()).join(';');
  return _fnv32('${domain}_${dims}_${prefill}_$constraints');
}

/// Return the index of the [n]-th `_` in [s], or -1 if not found.
int _nthUnderscore(String s, int n) {
  int count = 0;
  for (int i = 0; i < s.length; i++) {
    if (s[i] == '_' && ++count == n) return i;
  }
  return -1;
}

// ──────────────────────────────────────────────────────────────────────────
// Serialisation
// ──────────────────────────────────────────────────────────────────────────

int _cvToInt(CellValue v) => switch (v) {
  CellValue.black => 1,
  CellValue.white => 2,
  CellValue.purple => 3,
  _ => 0,
};

CellValue _intToCv(int i) => switch (i) {
  1 => CellValue.black,
  2 => CellValue.white,
  3 => CellValue.purple,
  _ => CellValue.free,
};

String _serializeStep(SolveStep step) {
  final bool isForce = step.method == SolveMethod.force;
  final String type;
  final int val;
  if (step is SetValueStep) {
    type = isForce ? 's' : 'S';
    val = _cvToInt(step.value);
  } else {
    final rs = step as RemoveOptionStep;
    type = isForce ? 'r' : 'R';
    val = _cvToInt(rs.option);
  }
  final cp = step.isComplicity ? 1 : 0;
  return '$type|${step.cellIdx}|$val|${step.complexity}|$cp|${step.forceDepth}|${step.constraint}';
}

SolveStep? _deserializeStep(String s) {
  try {
    // Split on the first 6 pipes only; constraint may contain '|' in theory.
    final parts = s.split('|');
    if (parts.length < 7) return null;
    final type = parts[0];
    final cellIdx = int.parse(parts[1]);
    final val = _intToCv(int.parse(parts[2]));
    final complexity = int.parse(parts[3]);
    final isComplicity = parts[4] == '1';
    final forceDepth = int.parse(parts[5]);
    // constraint is everything after the 6th pipe
    final constraint = parts.sublist(6).join('|');
    final method = type == type.toUpperCase()
        ? SolveMethod.propagation
        : SolveMethod.force;
    if (type == 'S' || type == 's') {
      return SetValueStep(
        cellIdx: cellIdx,
        value: val,
        constraint: constraint,
        method: method,
        complexity: complexity,
        isComplicity: isComplicity,
      );
    } else {
      return RemoveOptionStep(
        cellIdx: cellIdx,
        option: val,
        constraint: constraint,
        method: method,
        forceDepth: forceDepth,
        complexity: complexity,
        isComplicity: isComplicity,
      );
    }
  } catch (_) {
    return null;
  }
}

/// Serialize a full solving trace to a single-line string.
String serializeTrace(List<SolveStep> steps) =>
    steps.map(_serializeStep).join(';');

/// Deserialize a trace string produced by [serializeTrace].
List<SolveStep> deserializeTrace(String raw) {
  if (raw.isEmpty) return const [];
  return raw.split(';').map(_deserializeStep).whereType<SolveStep>().toList();
}

// ──────────────────────────────────────────────────────────────────────────
// Cache
// ──────────────────────────────────────────────────────────────────────────

/// In-memory trace cache, loaded from / saved to [kTraceCachePath].
///
/// Keyed by [traceKeyFromLine] / [traceKeyFromPuzzle] (the puzzle_hash).
/// The canonical_key column in the TSV file is kept only for human
/// readability and is not used for lookup.
class TraceCache {
  final Map<String, List<SolveStep>> _byHash;
  // Parallel map from hash → canonical_key, preserved across load/save so we
  // don't lose the human-readable labels for entries we didn't touch.
  final Map<String, String> _hashToKey;

  TraceCache._({
    required Map<String, List<SolveStep>> byHash,
    required Map<String, String> hashToKey,
  }) : _byHash = byHash,
       _hashToKey = hashToKey;

  /// Load the cache from [path]. Returns an empty cache when the file does not
  /// exist or is empty — callers should fall back to solving in that case.
  factory TraceCache.load(String path) {
    final file = File(path);
    if (!file.existsSync()) return TraceCache.empty();
    final byHash = <String, List<SolveStep>>{};
    final hashToKey = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final tab1 = line.indexOf('\t');
      if (tab1 < 0) continue;
      final tab2 = line.indexOf('\t', tab1 + 1);
      if (tab2 < 0) continue;
      final hash = line.substring(0, tab1);
      final key = line.substring(tab1 + 1, tab2);
      final traceRaw = line.substring(tab2 + 1);
      byHash[hash] = deserializeTrace(traceRaw);
      hashToKey[hash] = key;
    }
    return TraceCache._(byHash: byHash, hashToKey: hashToKey);
  }

  /// Create an empty cache (no file on disk yet).
  factory TraceCache.empty() => TraceCache._(byHash: {}, hashToKey: {});

  /// Look up the trace for a given puzzle hash. Returns `null` on miss.
  List<SolveStep>? lookup(String hash) => _byHash[hash];

  /// Store or replace the trace for a given puzzle hash.
  void update(String hash, String canonicalKey, List<SolveStep> steps) {
    _byHash[hash] = steps;
    _hashToKey[hash] = canonicalKey;
  }

  /// Number of entries in the cache.
  int get size => _byHash.length;

  /// Whether the cache contains any entries.
  bool get isEmpty => _byHash.isEmpty;

  /// Write the full cache back to [path].
  void save(String path) {
    final buf = StringBuffer();
    for (final entry in _byHash.entries) {
      final key = _hashToKey[entry.key] ?? '';
      buf.writeln('${entry.key}\t$key\t${serializeTrace(entry.value)}');
    }
    File(path).writeAsStringSync(buf.toString());
  }
}
