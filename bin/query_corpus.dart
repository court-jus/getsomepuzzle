/// Read-only query tool over the on-disk v2 puzzle corpus.
///
/// Scans one or more `assets/*.txt` files, applies filters (ntypes,
/// included/excluded slugs, width/height/area), and prints an aggregate
/// table grouped by the chosen axis. Pure Dart, no Flutter dependency —
/// runs as `dart run bin/query_corpus.dart …`.
///
/// See `docs/dev/collection_management.md` for usage examples.
library;

import 'dart:io';

// ---------------------------------------------------------------------------
// Collections (mirrors the filenames in `assets/`)
// ---------------------------------------------------------------------------

const _publishedFiles = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
];

const _rejectFiles = [
  'assets/cancelled.txt',
  'assets/noCandidates.txt',
  'assets/notUnique.txt',
  'assets/overfilled-easy.txt',
  'assets/overfilled.txt',
  'assets/ratioTooHigh.txt',
];

const _allFiles = [..._publishedFiles, ..._rejectFiles];

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _Puzzle {
  final String collection;
  final Set<String> slugs;
  final int width;
  final int height;
  final String scenario;
  _Puzzle(this.collection, this.slugs, this.width, this.height, this.scenario);
}

class _Filters {
  int? exactNtypes;
  int? minNtypes;
  int? maxNtypes;
  final Set<String> includeSlugs = {};
  final Set<String> excludeSlugs = {};
  final Set<int> widths = {};
  final Set<int> heights = {};
  int? minArea;
  int? maxArea;
}

class _Args {
  final List<String> files;
  final _Filters filters;
  final String groupBy;
  final int? top;
  final String sort;
  _Args(this.files, this.filters, this.groupBy, this.top, this.sort);
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Parse a single v2 line. Returns `null` for blank lines, comments, or
/// any line that doesn't match the expected
/// `v2_DOMAIN_WxH_CELLS_CONSTRAINTS_…` shape. Malformed lines are
/// silently skipped — the script is best-effort.
///
/// Field indices after `split('_')`:
///   [0] "v2"   [1] domain   [2] WxH   [3] cells   [4] constraints
///   [5..]  optional suffixes (cached solution, complexity, scenario, p:, …).
_Puzzle? _parseLine(String line, String collection) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
  if (!trimmed.startsWith('v2_')) return null;
  final parts = trimmed.split('_');
  if (parts.length < 5) return null;

  final dim = parts[2].split('x');
  if (dim.length != 2) return null;
  final w = int.tryParse(dim[0]);
  final h = int.tryParse(dim[1]);
  if (w == null || h == null) return null;

  final slugs = <String>{};
  for (final c in parts[4].split(';')) {
    if (c.isEmpty) continue;
    final s = c.split(':').first;
    if (s.isNotEmpty) slugs.add(s);
  }
  if (slugs.isEmpty) return null;

  // Authoritative scenario suffix: `_scenario:xxx` anywhere after the
  // constraint field. Absent → `classic`, same convention as
  // `detectPuzzleProfile` in `equilibrium.dart`.
  var scenario = 'classic';
  for (int i = 5; i < parts.length; i++) {
    if (parts[i].startsWith('scenario:')) {
      scenario = parts[i].substring('scenario:'.length);
      break;
    }
  }
  return _Puzzle(collection, slugs, w, h, scenario);
}

// ---------------------------------------------------------------------------
// Filtering & aggregation
// ---------------------------------------------------------------------------

bool _passesFilters(_Puzzle p, _Filters f) {
  final n = p.slugs.length;
  if (f.exactNtypes != null && n != f.exactNtypes) return false;
  if (f.minNtypes != null && n < f.minNtypes!) return false;
  if (f.maxNtypes != null && n > f.maxNtypes!) return false;
  for (final s in f.includeSlugs) {
    if (!p.slugs.contains(s)) return false;
  }
  for (final s in f.excludeSlugs) {
    if (p.slugs.contains(s)) return false;
  }
  if (f.widths.isNotEmpty && !f.widths.contains(p.width)) return false;
  if (f.heights.isNotEmpty && !f.heights.contains(p.height)) return false;
  final area = p.width * p.height;
  if (f.minArea != null && area < f.minArea!) return false;
  if (f.maxArea != null && area > f.maxArea!) return false;
  return true;
}

Map<String, int> _aggregate(Iterable<_Puzzle> puzzles, String groupBy) {
  final counts = <String, int>{};
  void bump(String key) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  for (final p in puzzles) {
    switch (groupBy) {
      case 'slug':
        // Each puzzle contributes to as many rows as it has distinct slugs.
        // The per-row share is therefore a *coverage* (puzzles containing
        // this slug / total filtered puzzles), which sums to ≥ 100 % when
        // multi-slug puzzles are present — that's by design.
        for (final s in p.slugs) {
          bump(s);
        }
        break;
      case 'ntypes':
        bump(p.slugs.length >= 6 ? '6+' : '${p.slugs.length}');
        break;
      case 'size':
        bump('${p.width}x${p.height}');
        break;
      case 'scenario':
        bump(p.scenario);
        break;
      case 'collection':
        bump(p.collection);
        break;
      default:
        throw ArgumentError('Unknown --group-by: $groupBy');
    }
  }
  return counts;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

void _printUsage(IOSink out) {
  out.writeln('Usage: dart run bin/query_corpus.dart [options]');
  out.writeln('');
  out.writeln('Filters (cumulative, AND):');
  out.writeln(
    '  --in FILE         Scan FILE. Repeatable. Keywords: "published"',
  );
  out.writeln('                    (default, six difficulty files), "all"');
  out.writeln('                    (every assets/*.txt incl. rejects).');
  out.writeln('  --ntypes N        Exact distinct-slug count.');
  out.writeln('  --min-ntypes N    Lower bound (inclusive).');
  out.writeln('  --max-ntypes N    Upper bound (inclusive).');
  out.writeln('  --include-slug X  Must contain X. Repeatable (AND).');
  out.writeln('  --exclude-slug X  Must NOT contain X. Repeatable.');
  out.writeln('  --width N         Exact width. Repeatable (OR).');
  out.writeln('  --height N        Exact height. Repeatable (OR).');
  out.writeln('  --min-area N      width*height >= N.');
  out.writeln('  --max-area N      width*height <= N.');
  out.writeln('');
  out.writeln('Output:');
  out.writeln('  --group-by AXIS   slug (default) | ntypes | size | scenario');
  out.writeln('                    | collection.');
  out.writeln('  --top N           Show only the top N rows.');
  out.writeln('  --sort count|key  Sort descending by count (default) or');
  out.writeln('                    alphanumerically by key.');
  out.writeln('  -h, --help        This message.');
  out.writeln('');
  out.writeln('Examples:');
  out.writeln('  dart run bin/query_corpus.dart --ntypes 1');
  out.writeln(
    '  dart run bin/query_corpus.dart --include-slug CH --exclude-slug SH \\',
  );
  out.writeln('        --group-by ntypes');
  out.writeln(
    '  dart run bin/query_corpus.dart --ntypes 1 --include-slug FM \\',
  );
  out.writeln('        --group-by size');
}

_Args _parseArgs(List<String> args) {
  final filters = _Filters();
  var files = <String>[];
  var pickedFiles = false;
  var groupBy = 'slug';
  int? top;
  var sort = 'count';

  String need(int i) {
    if (i + 1 >= args.length) {
      throw ArgumentError('Missing value for ${args[i]}');
    }
    return args[i + 1];
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h':
      case '--help':
        _printUsage(stdout);
        exit(0);
      case '--in':
        final v = need(i);
        i++;
        if (v == 'published') {
          files.addAll(_publishedFiles);
        } else if (v == 'all') {
          files.addAll(_allFiles);
        } else if (v == 'rejects') {
          files.addAll(_rejectFiles);
        } else {
          files.add(v);
        }
        pickedFiles = true;
        break;
      case '--ntypes':
        filters.exactNtypes = int.parse(need(i));
        i++;
        break;
      case '--min-ntypes':
        filters.minNtypes = int.parse(need(i));
        i++;
        break;
      case '--max-ntypes':
        filters.maxNtypes = int.parse(need(i));
        i++;
        break;
      case '--include-slug':
        filters.includeSlugs.add(need(i));
        i++;
        break;
      case '--exclude-slug':
        filters.excludeSlugs.add(need(i));
        i++;
        break;
      case '--width':
        filters.widths.add(int.parse(need(i)));
        i++;
        break;
      case '--height':
        filters.heights.add(int.parse(need(i)));
        i++;
        break;
      case '--min-area':
        filters.minArea = int.parse(need(i));
        i++;
        break;
      case '--max-area':
        filters.maxArea = int.parse(need(i));
        i++;
        break;
      case '--group-by':
        groupBy = need(i);
        i++;
        const valid = {'slug', 'ntypes', 'size', 'scenario', 'collection'};
        if (!valid.contains(groupBy)) {
          throw ArgumentError(
            'Invalid --group-by: $groupBy. Expected one of $valid.',
          );
        }
        break;
      case '--top':
        top = int.parse(need(i));
        i++;
        break;
      case '--sort':
        sort = need(i);
        i++;
        if (sort != 'count' && sort != 'key') {
          throw ArgumentError('Invalid --sort: $sort. Expected count|key.');
        }
        break;
      default:
        throw ArgumentError('Unknown option: $a (use --help).');
    }
  }
  if (!pickedFiles) files = List<String>.from(_publishedFiles);
  return _Args(files, filters, groupBy, top, sort);
}

void main(List<String> rawArgs) {
  final _Args opts;
  try {
    opts = _parseArgs(rawArgs);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln('');
    _printUsage(stderr);
    exit(2);
  }

  final puzzles = <_Puzzle>[];
  var totalScanned = 0;
  for (final path in opts.files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Warning: file not found, skipped: $path');
      continue;
    }
    for (final line in file.readAsLinesSync()) {
      final p = _parseLine(line, path);
      if (p == null) continue;
      totalScanned++;
      puzzles.add(p);
    }
  }

  final filtered = puzzles
      .where((p) => _passesFilters(p, opts.filters))
      .toList();
  final counts = _aggregate(filtered, opts.groupBy);

  // Header
  stdout.writeln(
    'Scanned files (${opts.files.length}): ${opts.files.join(", ")}',
  );
  stdout.writeln('Total puzzles: $totalScanned');
  final pct = totalScanned == 0 ? 0.0 : filtered.length * 100 / totalScanned;
  stdout.writeln(
    'After filters: ${filtered.length} (${pct.toStringAsFixed(2)}% of total)',
  );

  final active = <String>[];
  if (opts.filters.exactNtypes != null) {
    active.add('ntypes=${opts.filters.exactNtypes}');
  }
  if (opts.filters.minNtypes != null) {
    active.add('ntypes>=${opts.filters.minNtypes}');
  }
  if (opts.filters.maxNtypes != null) {
    active.add('ntypes<=${opts.filters.maxNtypes}');
  }
  if (opts.filters.includeSlugs.isNotEmpty) {
    active.add('+slugs={${opts.filters.includeSlugs.join(',')}}');
  }
  if (opts.filters.excludeSlugs.isNotEmpty) {
    active.add('-slugs={${opts.filters.excludeSlugs.join(',')}}');
  }
  if (opts.filters.widths.isNotEmpty) {
    active.add('width={${opts.filters.widths.join(',')}}');
  }
  if (opts.filters.heights.isNotEmpty) {
    active.add('height={${opts.filters.heights.join(',')}}');
  }
  if (opts.filters.minArea != null) active.add('area>=${opts.filters.minArea}');
  if (opts.filters.maxArea != null) active.add('area<=${opts.filters.maxArea}');
  if (active.isNotEmpty) {
    stdout.writeln('Filters: ${active.join(' ')}');
  }
  stdout.writeln('');

  // Table
  final headerKey = opts.groupBy;
  var entries = counts.entries.toList();
  if (opts.sort == 'count') {
    entries.sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  } else {
    entries.sort((a, b) => a.key.compareTo(b.key));
  }
  if (opts.top != null && entries.length > opts.top!) {
    entries = entries.sublist(0, opts.top!);
  }

  // Column widths
  final keyWidth = [
    headerKey.length,
    ...entries.map((e) => e.key.length),
  ].reduce((a, b) => a > b ? a : b);
  final countWidth = [
    'count'.length,
    ...entries.map((e) => e.value.toString().length),
  ].reduce((a, b) => a > b ? a : b);

  stdout.writeln(
    '${headerKey.padRight(keyWidth)}    ${'count'.padLeft(countWidth)}    share',
  );
  stdout.writeln('${'-' * keyWidth}    ${'-' * countWidth}    -----');
  final denom = filtered.length;
  for (final e in entries) {
    final share = denom == 0 ? 0.0 : e.value * 100 / denom;
    stdout.writeln(
      '${e.key.padRight(keyWidth)}    '
      '${e.value.toString().padLeft(countWidth)}    '
      '${share.toStringAsFixed(1).padLeft(5)}%',
    );
  }

  if (opts.groupBy == 'slug' && filtered.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln(
      '(slug groupings count puzzle coverage; per-row share is '
      'puzzles-containing-this-slug / total filtered, and may sum to > 100% '
      'when multi-slug puzzles are present.)',
    );
  }
}
