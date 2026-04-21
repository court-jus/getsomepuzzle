/// A parsed stat line from the stats files.
/// Format: finishedTimestamp durationS failuresF puzzleLine - SLD - extras
/// The extras block contains: skipped - liked - disliked - pleasure - hintsH.
/// The trailing `hintsH` field was added later — older lines without it
/// parse with hints=0.
class StatEntry {
  final String? finished;
  final int duration;
  final int failures;
  final int hints;
  final String puzzleLine;
  final String? skipped;
  final String? liked;
  final String? disliked;
  final int? pleasure;

  @override
  String toString() =>
      '${finished ?? "unfinished"} ${duration}s ${failures}f $puzzleLine';

  const StatEntry({
    required this.finished,
    required this.duration,
    required this.failures,
    required this.puzzleLine,
    this.hints = 0,
    this.skipped,
    this.liked,
    this.disliked,
    this.pleasure,
  });

  /// Parse a stat line. Returns null if the line is invalid.
  static StatEntry? parse(String line) {
    final fields = line.split(' ');
    if (fields.length < 4) return null;
    final finished = fields[0] == 'unfinished' ? null : fields[0];
    final duration = int.tryParse(fields[1].replaceAll('s', ''));
    final failures = int.tryParse(fields[2].replaceAll('f', ''));
    if (duration == null || failures == null) return null;
    final hints = fields.length > 15
        ? int.tryParse(fields[15].replaceAll('h', '')) ?? 0
        : 0;
    return StatEntry(
      finished: finished,
      duration: duration,
      failures: failures,
      hints: hints,
      puzzleLine: fields[3],
      skipped: fields.length > 7 && fields[7].isNotEmpty ? fields[7] : null,
      liked: fields.length > 9 && fields[9].isNotEmpty ? fields[9] : null,
      disliked: fields.length > 11 && fields[11].isNotEmpty ? fields[11] : null,
      pleasure: fields.length > 13 ? int.tryParse(fields[13]) : null,
    );
  }
}

/// Aggregated stats for a single puzzle across multiple plays.
class PuzzleAggregatedStats {
  int total = 0;
  int duration = 0;
  int failures = 0;

  void add(StatEntry entry) {
    total++;
    duration += entry.duration;
    failures += entry.failures;
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
