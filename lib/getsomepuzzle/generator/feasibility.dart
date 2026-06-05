import 'dart:io';

/// Canonical identity of an attempt's parameter combination. Two attempts
/// share the same [AttemptKey] when they ask the generator for an identical
/// task — the right granularity for "this combo never succeeds, stop trying".
///
/// Tuple chosen to match what `generator_stats.csv` captures, so the in-
/// session tracker and the persistent CSV-driven seed share one vocabulary:
/// `targetKey` (the equilibrium axis being pushed), `sortedSlugs` (the soft
/// preference set), `scenario` (pre-fill mode), and `sizeBucket` (a coarse
/// area class — CH might be infeasible on tiny grids and feasible on large
/// ones, so we shouldn't collapse all sizes into one).
class AttemptKey {
  /// `Target.key` (e.g. `slug:CH`, `ntypes:1`, `profile:pathBased`) or
  /// `'none'` when no equilibrium target was picked (warmup, or non-
  /// equilibrium random pick).
  final String targetKey;

  /// `preferredSlugs.toList()..sort()` so `{CH, SY}` and `{SY, CH}` hash the
  /// same. Empty list when the iterative loop is fully unconstrained.
  final List<String> sortedSlugs;

  /// `classic` / `sh` / `pathBased` / `syBased` — resolved by the worker's
  /// `_resolveScenario` helper.
  final String scenario;

  /// `bucketForArea(w, h)` — one of `≤20`, `21-40`, `41-80`, `>80`.
  final String sizeBucket;

  AttemptKey({
    required this.targetKey,
    required this.sortedSlugs,
    required this.scenario,
    required this.sizeBucket,
  });

  /// Stable text form used as Map / Set key. Pipe-separated because slugs
  /// are joined with `,` inside the second field.
  String get serialized =>
      '$targetKey|${sortedSlugs.join(',')}|$scenario|$sizeBucket';
}

/// Scenario field of an [AttemptKey], augmented with the attempt's colour
/// domain when it departs from the historical default. Domain-2 attempts
/// keep the bare scenario (`classic`, `sh`, …) so every key serialized
/// before the domain axis existed stays valid; domain-3 attempts get a
/// `+d3` suffix so the blacklist never conflates the two populations
/// (their success rates differ widely). Shared by the worker (key
/// construction) and [readPersistentBlacklist] (CSV re-aggregation) so
/// the two sides cannot drift. The suffix lives only in the key — the
/// `scenario` CSV column and the profile axis stay unsuffixed.
String attemptScenarioKey(String scenario, int domainSize) =>
    domainSize == 3 ? '$scenario+d3' : scenario;

/// Coarse area buckets used as part of the feasibility blacklist key (and the
/// CSV analysis). Kept deliberately stable so existing persisted blacklist
/// entries stay valid — the dashboard in `bin/generate.dart` now renders a
/// finer partition (`kSizeBucketLabels`) purely for display.
String bucketForArea(int width, int height) {
  final area = width * height;
  if (area <= 20) return '≤20';
  if (area <= 40) return '21-40';
  if (area <= 80) return '41-80';
  return '>80';
}

class _ComboStats {
  int attempts = 0;
  int successes = 0;
}

/// Per-worker, in-memory counter. The worker calls [record] after every
/// `generateOne()` attempt (success or abandon), and queries
/// [isBlacklisted] before the next attempt to decide whether to skip.
///
/// Lives for the duration of one CLI run. Cross-run persistence is handled
/// separately by [readPersistentBlacklist] reading `generator_stats.csv`.
class InfeasibilityTracker {
  final Map<String, _ComboStats> _stats = {};

  void record(AttemptKey key, {required bool success}) {
    final stat = _stats.putIfAbsent(key.serialized, _ComboStats.new);
    stat.attempts++;
    if (success) stat.successes++;
  }

  bool isBlacklisted(AttemptKey key, {required int kThreshold}) {
    final stat = _stats[key.serialized];
    if (stat == null) return false;
    return stat.attempts >= kThreshold && stat.successes == 0;
  }
}

/// Reads `generator_stats.csv` (when present) and returns the set of
/// serialized [AttemptKey]s that have been tried at least [minAttempts]
/// times with zero successes across all logged runs. Used to seed worker
/// blacklists so the second run onwards doesn't re-discover impossibilities
/// the first run already proved.
///
/// Returns an empty set when the file is missing, empty, or contains only
/// the header. Malformed rows are silently skipped — the CSV is best-effort
/// telemetry, not a source of truth.
Set<String> readPersistentBlacklist({
  required String csvPath,
  required int minAttempts,
}) {
  final file = File(csvPath);
  if (!file.existsSync()) return const <String>{};

  final lines = file.readAsLinesSync();
  if (lines.length <= 1) return const <String>{};

  // Column positions are fixed by `_statsColumns` in `bin/generate.dart`:
  //   4=target_key, 5=width, 6=height, 8=preferred_slugs, 10=scenario,
  //   11=outcome, 17=domain (absent on rows written before the domain
  //   axis — those are all dom-2, the historical default). The split is
  //   quote-aware so the `puzzle_line` column (15), which may contain
  //   escaped commas, can't shift the columns after it.
  final aggregated = <String, _ComboStats>{};
  for (int i = 1; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trim().isEmpty) continue;
    final parts = _splitCsvRow(raw);
    if (parts.length < 12) continue;
    final targetKey = parts[4].isEmpty ? 'none' : parts[4];
    final width = int.tryParse(parts[5]);
    final height = int.tryParse(parts[6]);
    if (width == null || height == null) continue;
    final preferredSlugs = parts[8].isEmpty
        ? const <String>[]
        : parts[8].split('|');
    final scenario = parts[10];
    final outcome = parts[11];
    final domainSize = parts.length > 17 ? (int.tryParse(parts[17]) ?? 2) : 2;

    final key = AttemptKey(
      targetKey: targetKey,
      sortedSlugs: [...preferredSlugs]..sort(),
      // Same rule as the worker's key construction — the shared helper
      // guarantees a CSV row re-serializes to the exact in-session key.
      scenario: attemptScenarioKey(scenario, domainSize),
      sizeBucket: bucketForArea(width, height),
    );
    final stat = aggregated.putIfAbsent(key.serialized, _ComboStats.new);
    stat.attempts++;
    if (outcome == 'success') stat.successes++;
  }

  return {
    for (final e in aggregated.entries)
      if (e.value.attempts >= minAttempts && e.value.successes == 0) e.key,
  };
}

/// Minimal RFC-4180-ish row splitter: handles `"`-quoted fields containing
/// commas and doubled-quote escapes, which is exactly what `_csvField` in
/// `bin/generate.dart` produces (no embedded newlines — the writer strips
/// them by construction, one row per line).
List<String> _splitCsvRow(String row) {
  final out = <String>[];
  final field = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < row.length; i++) {
    final ch = row[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < row.length && row[i + 1] == '"') {
          field.write('"');
          i++; // escaped quote
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      out.add(field.toString());
      field.clear();
    } else {
      field.write(ch);
    }
  }
  out.add(field.toString());
  return out;
}
