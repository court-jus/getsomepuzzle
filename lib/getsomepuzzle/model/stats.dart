import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';

/// A parsed stat line from the stats files.
/// Format: finishedTimestamp durationS failuresF puzzleLine - SLD - extras
/// The extras block contains in order:
///   skipped - liked - disliked - pleasure - hintsH - cellEditsE
///   - firstClickMsFC - longestGapMsLG
/// New fields are appended over time; older lines parse with the defaults
/// `hints=cellEdits=firstClickMs=longestGapMs=0`.
class StatEntry {
  final String? finished;
  final int duration;
  final int failures;
  final int hints;
  final int cellEdits;
  final int firstClickMs;
  final int longestGapMs;
  final String puzzleLine;
  final String? skipped;
  final String? liked;
  final String? disliked;
  final int? pleasure;

  /// The original line this entry was parsed from, when it came out of
  /// [parse]. Persistence must round-trip through this verbatim rather
  /// than through [toString], which is the minimal 4-field form and
  /// drops every trailing metadata field (ratings, hints, click
  /// analytics, skip markers).
  final String? raw;

  @override
  String toString() =>
      '${finished ?? "unfinished"} ${duration}s ${failures}f $puzzleLine';

  const StatEntry({
    required this.finished,
    required this.duration,
    required this.failures,
    required this.puzzleLine,
    this.hints = 0,
    this.cellEdits = 0,
    this.firstClickMs = 0,
    this.longestGapMs = 0,
    this.skipped,
    this.liked,
    this.disliked,
    this.pleasure,
    this.raw,
  });

  /// The full persisted line: the verbatim [raw] line when this entry
  /// was parsed, otherwise a reconstruction in the same grammar
  /// `PuzzleData.getStat()` emits (`- SLD -` block + suffix-tagged
  /// extras). Keeps ratings/hints/skip markers on disk across flushes.
  String fullLine() {
    if (raw != null) return raw!;
    final sld = [
      skipped != null ? "S" : "_",
      liked != null ? "L" : "_",
      disliked != null ? "D" : "_",
    ].join("");
    final extraFields = [
      skipped ?? "",
      liked ?? "",
      disliked ?? "",
      pleasure?.toString() ?? "",
      "${hints}h",
      "${cellEdits}e",
      "${firstClickMs}fc",
      "${longestGapMs}lg",
    ].join(" - ");
    return '${finished ?? "unfinished"} ${duration}s ${failures}f '
        '$puzzleLine - $sld - $extraFields';
  }

  /// Parse a stat line. Returns null if the line is invalid.
  static StatEntry? parse(String line) {
    final fields = line.split(' ');
    if (fields.length < 4) return null;
    final finished = fields[0] == 'unfinished' ? null : fields[0];
    final duration = int.tryParse(fields[1].replaceAll('s', ''));
    final failures = int.tryParse(fields[2].replaceAll('f', ''));
    if (duration == null || failures == null) return null;
    // Suffix-tagged fields appended at the end of the line in order. We look
    // them up by suffix rather than position so future fields can slot in
    // without breaking parsers — and so old lines that lack them still parse.
    int parseSuffixed(String suffix) {
      for (final f in fields) {
        if (f.endsWith(suffix)) {
          return int.tryParse(f.substring(0, f.length - suffix.length)) ?? 0;
        }
      }
      return 0;
    }

    return StatEntry(
      finished: finished,
      duration: duration,
      failures: failures,
      hints: parseSuffixed('h'),
      cellEdits: parseSuffixed('e'),
      firstClickMs: parseSuffixed('fc'),
      longestGapMs: parseSuffixed('lg'),
      puzzleLine: fields[3],
      skipped: fields.length > 7 && fields[7].isNotEmpty ? fields[7] : null,
      liked: fields.length > 9 && fields[9].isNotEmpty ? fields[9] : null,
      disliked: fields.length > 11 && fields[11].isNotEmpty ? fields[11] : null,
      pleasure: fields.length > 13 ? int.tryParse(fields[13]) : null,
      raw: line,
    );
  }
}

/// Aggregated stats for a single puzzle across multiple plays.
class PuzzleAggregatedStats {
  int total = 0;
  int duration = 0;
  int failures = 0;
  int hints = 0;

  void add(StatEntry entry) {
    total++;
    duration += entry.duration;
    failures += entry.failures;
    hints += entry.hints;
  }

  /// Difficulty level: avg duration + 30 * avg failures.
  int get level {
    if (total == 0) return 0;
    return (duration / total + 30 * failures / total).toInt();
  }
}

/// Parse stat lines and aggregate by puzzle.
/// Returns a map of puzzleLine → aggregated stats.
Map<String, PuzzleAggregatedStats> aggregateStats(List<String> lines) {
  final result = <String, PuzzleAggregatedStats>{};
  for (final line in lines) {
    final entry = StatEntry.parse(line);
    if (entry == null) continue;
    result.putIfAbsent(entry.puzzleLine, () => PuzzleAggregatedStats());
    result[entry.puzzleLine]!.add(entry);
  }
  return result;
}

/// Sort puzzles by difficulty level (ascending).
List<String> sortPuzzlesByDifficulty(Map<String, PuzzleAggregatedStats> stats) {
  final entries = stats.entries.toList()
    ..sort((a, b) => a.value.level.compareTo(b.value.level));
  return entries.map((e) => e.key).toList();
}

/// A difficulty bucket grouping puzzles by cplx range.
class DifficultyBucket {
  final String label;
  final int count;
  final double avgDuration;
  final double avgHints;

  const DifficultyBucket({
    required this.label,
    required this.count,
    required this.avgDuration,
    required this.avgHints,
  });
}

/// A constraint bucket grouping puzzles by constraint slug.
class ConstraintBucket {
  final String slug;
  final int puzzleCount;
  final int instanceCount;
  final double avgDuration;
  final double avgHints;

  const ConstraintBucket({
    required this.slug,
    required this.puzzleCount,
    required this.instanceCount,
    required this.avgDuration,
    required this.avgHints,
  });
}

/// A collection bucket grouping puzzles by collection.
class CollectionBucket {
  final String label;
  final int count;
  final double avgDuration;
  final double avgHints;

  const CollectionBucket({
    required this.label,
    required this.count,
    required this.avgDuration,
    required this.avgHints,
  });
}

int _extractCplx(String puzzleLine) {
  final parts = puzzleLine.split('_');
  return parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
}

List<String> _extractSlugs(String puzzleLine) {
  final parts = puzzleLine.split('_');
  if (parts.length < 5) return [];
  return parts[4].split(';').map((c) => c.split(':')[0]).toList();
}

/// Aggregated stats dashboard computed from raw [StatEntry] list.
class StatsDashboard {
  /// [collectionLookup] maps an [identityKey] to a collection label.
  StatsDashboard(List<StatEntry> raw, {Map<String, String>? collectionLookup}) {
    for (final entry in raw) {
      _totalPlays++;
      if (entry.finished != null) {
        _finishedPlays++;
      }
      _sumDuration += entry.duration;
      _sumFailures += entry.failures;
      _sumHints += entry.hints;

      // By difficulty
      final cplx = _extractCplx(entry.puzzleLine);
      final bucket = _bucketLabel(cplx);
      _difficultyBuckets.putIfAbsent(bucket, () => _BucketAccumulator());
      _difficultyBuckets[bucket]!.add(entry);

      // By constraint
      final allSlugs = _extractSlugs(entry.puzzleLine);
      final uniqueSlugs = allSlugs.toSet();
      for (final slug in uniqueSlugs) {
        _constraintBuckets.putIfAbsent(slug, () => _ConstraintAccumulator());
        _constraintBuckets[slug]!.puzzleCount++;
        _constraintBuckets[slug]!.sumDuration += entry.duration;
        _constraintBuckets[slug]!.sumHints += entry.hints;
      }
      for (final slug in allSlugs) {
        _constraintBuckets[slug]!.instanceCount++;
      }

      // By collection
      if (collectionLookup != null) {
        final key = identityKey(entry.puzzleLine);
        final col = collectionLookup[key] ?? 'other';
        _collectionBuckets.putIfAbsent(col, () => _BucketAccumulator());
        _collectionBuckets[col]!.add(entry);
      }

      // Rating
      if (entry.pleasure != null) {
        if (entry.pleasure! > 0) _likes++;
        if (entry.pleasure! < 0) _dislikes++;
        _sumPleasure += entry.pleasure!;
        _pleasureCount++;
      }

      // Recent plays (keep track, sort later)
      if (entry.finished != null) {
        _allPlays.add(entry);
      }
    }

    // Build difficulty buckets
    for (final label in _allBuckets) {
      final bucket = _difficultyBuckets[label];
      if (bucket == null) {
        byDifficulty.add(
          DifficultyBucket(label: label, count: 0, avgDuration: 0, avgHints: 0),
        );
      } else {
        byDifficulty.add(
          DifficultyBucket(
            label: label,
            count: bucket.count,
            avgDuration: bucket.count > 0
                ? bucket.sumDuration / bucket.count
                : 0,
            avgHints: bucket.count > 0 ? bucket.sumHints / bucket.count : 0,
          ),
        );
      }
    }

    // Build constraint buckets (top 5 by instanceCount)
    final sortedSlugs = _constraintBuckets.entries.toList()
      ..sort((a, b) => b.value.instanceCount.compareTo(a.value.instanceCount));
    for (final entry in sortedSlugs.take(5)) {
      byConstraint.add(
        ConstraintBucket(
          slug: entry.key,
          puzzleCount: entry.value.puzzleCount,
          instanceCount: entry.value.instanceCount,
          avgDuration: entry.value.puzzleCount > 0
              ? entry.value.sumDuration / entry.value.puzzleCount
              : 0,
          avgHints: entry.value.puzzleCount > 0
              ? entry.value.sumHints / entry.value.puzzleCount
              : 0,
        ),
      );
    }

    // Build collection buckets
    final sortedCollections = _collectionBuckets.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));
    for (final entry in sortedCollections) {
      byCollection.add(
        CollectionBucket(
          label: entry.key,
          count: entry.value.count,
          avgDuration: entry.value.count > 0
              ? entry.value.sumDuration / entry.value.count
              : 0,
          avgHints: entry.value.count > 0
              ? entry.value.sumHints / entry.value.count
              : 0,
        ),
      );
    }

    // Sort recent plays by finished timestamp descending, take 10
    _allPlays.sort((a, b) => b.finished!.compareTo(a.finished!));
    recentPlays = _allPlays.take(10).toList();
  }

  // Raw accumulated data
  int _totalPlays = 0;
  int _finishedPlays = 0;
  int _sumDuration = 0;
  int _sumFailures = 0;
  int _sumHints = 0;
  int _likes = 0;
  int _dislikes = 0;
  int _sumPleasure = 0;
  int _pleasureCount = 0;
  final List<StatEntry> _allPlays = [];
  final Map<String, _BucketAccumulator> _difficultyBuckets = {};
  final Map<String, _ConstraintAccumulator> _constraintBuckets = {};
  final Map<String, _BucketAccumulator> _collectionBuckets = {};

  // Computed results
  final List<DifficultyBucket> byDifficulty = [];
  final List<ConstraintBucket> byConstraint = [];
  final List<CollectionBucket> byCollection = [];
  late final List<StatEntry> recentPlays;

  // Computed getters
  int get totalPlays => _totalPlays;
  int get finishedPlays => _finishedPlays;
  int get skippedPlays => _totalPlays - _finishedPlays;
  double get avgDuration => _totalPlays > 0 ? _sumDuration / _totalPlays : 0;
  double get avgFailures => _totalPlays > 0 ? _sumFailures / _totalPlays : 0;
  int get totalHints => _sumHints;
  double get avgHintsPerPuzzle => _totalPlays > 0 ? _sumHints / _totalPlays : 0;
  int get likes => _likes;
  int get dislikes => _dislikes;
  double? get avgPleasure =>
      _pleasureCount > 0 ? _sumPleasure / _pleasureCount : null;

  static String _bucketLabel(int cplx) {
    if (cplx <= 20) return '0-20';
    if (cplx <= 40) return '21-40';
    if (cplx <= 60) return '41-60';
    if (cplx <= 80) return '61-80';
    if (cplx <= 100) return '81-100';
    // Complexity is unbounded; hard puzzles pile up past 100.
    return '101+';
  }

  static const _allBuckets = [
    '0-20',
    '21-40',
    '41-60',
    '61-80',
    '81-100',
    '101+',
  ];
}

class _BucketAccumulator {
  int count = 0;
  int sumDuration = 0;
  int sumHints = 0;

  void add(StatEntry entry) {
    count++;
    sumDuration += entry.duration;
    sumHints += entry.hints;
  }
}

class _ConstraintAccumulator {
  int puzzleCount = 0;
  int instanceCount = 0;
  int sumDuration = 0;
  int sumHints = 0;
}
