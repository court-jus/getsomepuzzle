/// Read-only query tool over the on-disk v2 puzzle corpus.
///
/// Scans one or more `assets/*.txt` files, applies filters (ntypes,
/// included/excluded slugs, width/height/area), and prints one of: a 1-D
/// table grouped by one axis (`--group-by`), a two-axis cross-tabulation
/// (`--cross AXIS1,AXIS2`), or the full joint-bucket inventory
/// (`--buckets`). Pure Dart, no Flutter dependency —
/// runs as `dart run bin/query_corpus.dart …`.
///
/// See `docs/dev/collection_management.md` for usage examples.
library;

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/constraints/families.dart';

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

  /// The ordered top-3 composition triple joined with '+', e.g.
  /// "path+line-centric+local". Precomputed from raw slug instances so the
  /// instance-count ranking matches [compositionOf] exactly.
  final String compositionKey;

  _Puzzle(
    this.collection,
    this.slugs,
    this.width,
    this.height,
    this.scenario,
    this.compositionKey,
  );
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

  /// `[rowAxis, colAxis]` for the 2-D cross-tabulation mode, or `null` for
  /// the default 1-D `groupBy` table.
  final List<String>? cross;

  /// Dimensions forming the joint bucket key (subset of {size, ntypes, slugs,
  /// scenario}) for the `--buckets` mode, or `null` when not requested.
  final List<String>? buckets;
  final int? top;
  final String sort;

  /// Flip the order produced by [sort]. Combined with [top] this surfaces the
  /// bottom of the ranking (e.g. the least-represented slug pairs).
  final bool reverse;
  _Args(
    this.files,
    this.filters,
    this.groupBy,
    this.cross,
    this.buckets,
    this.top,
    this.sort,
    this.reverse,
  );
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

  // Collect raw slug instances (with repeats) for composition computation,
  // then derive the deduplicated set for slug/ntypes tracking.
  final rawSlugs = <String>[];
  for (final c in parts[4].split(';')) {
    if (c.isEmpty) continue;
    final s = c.split(':').first;
    if (s.isNotEmpty) rawSlugs.add(s);
  }
  final slugs = rawSlugs.toSet();
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
  final comp = compositionOf(rawSlugs);
  final compKey = comp.join('+');
  return _Puzzle(collection, slugs, w, h, scenario, compKey);
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

/// Orientation-agnostic size label `min x max`, so `4x5` and `5x4` collapse
/// to a single bin — mirrors `canonicalSize` in `equilibrium.dart`, where the
/// generator's size axis treats a shape and its transpose as one category.
String _sizeKey(_Puzzle p) {
  final a = p.width <= p.height ? p.width : p.height;
  final b = p.width <= p.height ? p.height : p.width;
  return '${a}x$b';
}

/// All keys a puzzle contributes to along [axis]. Single-valued for every
/// axis except `slug`, where a puzzle yields one key per distinct slug —
/// so slug-axis marginals count *coverage* (puzzles containing this slug),
/// which sums to ≥ 100 % when multi-slug puzzles are present, by design.
Iterable<String> _keysFor(_Puzzle p, String axis) {
  switch (axis) {
    case 'slug':
      return p.slugs;
    case 'ntypes':
      return [p.slugs.length >= 6 ? '6+' : '${p.slugs.length}'];
    case 'size':
      return [_sizeKey(p)];
    case 'scenario':
      return [p.scenario];
    case 'collection':
      return [p.collection];
    case 'composition':
      return [p.compositionKey];
    default:
      throw ArgumentError('Unknown axis: $axis');
  }
}

Map<String, int> _aggregate(Iterable<_Puzzle> puzzles, String groupBy) {
  final counts = <String, int>{};
  for (final p in puzzles) {
    for (final key in _keysFor(p, groupBy)) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return counts;
}

/// 2-D cross-tabulation: `cell[rowKey][colKey]` = number of (puzzle, key)
/// pairs landing in that cross. A puzzle multiplies out across both axes,
/// so for `slug × slug` a puzzle with slugs {FM, PA} fills (FM,FM), (FM,PA),
/// (PA,FM), (PA,PA) — a symmetric co-occurrence matrix whose diagonal is the
/// per-slug coverage.
Map<String, Map<String, int>> _crosstab(
  Iterable<_Puzzle> puzzles,
  String rowAxis,
  String colAxis,
) {
  final cells = <String, Map<String, int>>{};
  for (final p in puzzles) {
    for (final r in _keysFor(p, rowAxis)) {
      final row = cells.putIfAbsent(r, () => <String, int>{});
      for (final c in _keysFor(p, colAxis)) {
        row[c] = (row[c] ?? 0) + 1;
      }
    }
  }
  return cells;
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
  out.writeln('                    | collection | composition.');
  out.writeln('  --cross A,B       Two-axis cross-tab: A as rows, B as');
  out.writeln('                    columns (same axis names as --group-by;');
  out.writeln('                    A and B may be equal). Mutually exclusive');
  out.writeln('                    with --group-by. Cells show count (row %).');
  out.writeln('  --buckets [DIMS]  List every distinct joint bucket and its');
  out.writeln('                    population. DIMS is a comma list over');
  out.writeln(
    '                    {size, ntypes, slugs, scenario, composition}; default',
  );
  out.writeln('                    size,slugs,scenario. "slugs" is the whole');
  out.writeln('                    sorted set (one atomic key, not per-slug).');
  out.writeln(
    '                    Mutually exclusive with --group-by/--cross.',
  );
  out.writeln('  --top N           Show only the top N rows (and N columns');
  out.writeln('                    in --cross mode).');
  out.writeln('  --sort count|key  Sort descending by count (default) or');
  out.writeln('                    alphanumerically by key.');
  out.writeln('  --reverse         Flip the sort order. With --top this');
  out.writeln('                    surfaces the bottom of the ranking (e.g.');
  out.writeln('                    the least-represented rows/columns).');
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
  out.writeln('  dart run bin/query_corpus.dart --cross slug,collection');
  out.writeln('  dart run bin/query_corpus.dart --cross slug,slug --ntypes 2');
  out.writeln(
    '  dart run bin/query_corpus.dart --cross slug,slug --ntypes 2 \\',
  );
  out.writeln('        --reverse --top 8   # least-represented slug pairs');
  out.writeln(
    '  dart run bin/query_corpus.dart --buckets --sort count --top 20',
  );
  out.writeln(
    '        # most over-populated joint (size, slug-set, scenario) tuples',
  );
}

_Args _parseArgs(List<String> args) {
  final filters = _Filters();
  var files = <String>[];
  var pickedFiles = false;
  var groupBy = 'slug';
  var groupBySet = false;
  List<String>? cross;
  List<String>? buckets;
  int? top;
  var sort = 'count';
  var reverse = false;

  const validAxes = {
    'slug',
    'ntypes',
    'size',
    'scenario',
    'collection',
    'composition',
  };
  const validBucketDims = {
    'size',
    'ntypes',
    'slugs',
    'scenario',
    'composition',
  };
  const defaultBucketDims = ['size', 'slugs', 'scenario'];

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
        groupBySet = true;
        if (!validAxes.contains(groupBy)) {
          throw ArgumentError(
            'Invalid --group-by: $groupBy. Expected one of $validAxes.',
          );
        }
        break;
      case '--cross':
        final axes = need(i).split(',').map((s) => s.trim()).toList();
        i++;
        if (axes.length != 2) {
          throw ArgumentError(
            'Invalid --cross: expected two comma-separated axes, e.g. '
            'slug,collection.',
          );
        }
        for (final ax in axes) {
          if (!validAxes.contains(ax)) {
            throw ArgumentError(
              'Invalid --cross axis: $ax. Expected one of $validAxes.',
            );
          }
        }
        cross = axes;
        break;
      case '--buckets':
        // Dimensions are optional: a following token that doesn't look like a
        // flag is consumed as the comma-separated dimension list, otherwise
        // the default joint key (size, slugs, scenario) is used.
        var dims = List<String>.from(defaultBucketDims);
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          dims = args[i + 1].split(',').map((s) => s.trim()).toList();
          i++;
          if (dims.isEmpty || dims.any((d) => d.isEmpty)) {
            throw ArgumentError('Invalid --buckets: empty dimension.');
          }
          for (final d in dims) {
            if (!validBucketDims.contains(d)) {
              throw ArgumentError(
                'Invalid --buckets dimension: $d. Expected one of '
                '$validBucketDims.',
              );
            }
          }
          if (dims.toSet().length != dims.length) {
            throw ArgumentError('Invalid --buckets: duplicate dimension.');
          }
        }
        buckets = dims;
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
      case '--reverse':
        reverse = true;
        break;
      default:
        throw ArgumentError('Unknown option: $a (use --help).');
    }
  }
  final modes = [
    if (groupBySet) '--group-by',
    if (cross != null) '--cross',
    if (buckets != null) '--buckets',
  ];
  if (modes.length > 1) {
    throw ArgumentError(
      '${modes.join(', ')} are mutually exclusive; pick one output mode.',
    );
  }
  if (!pickedFiles) files = List<String>.from(_publishedFiles);
  return _Args(files, filters, groupBy, cross, buckets, top, sort, reverse);
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

  if (opts.cross != null) {
    _printCrosstab(filtered, opts);
  } else if (opts.buckets != null) {
    _printBuckets(filtered, opts);
  } else {
    _printTable1D(filtered, opts);
  }
}

/// Sort `keys` per `--sort`: descending by `weight` (count marginal) with an
/// alphanumeric tie-break, or alphanumerically when `sort == 'key'`. When
/// `reverse` is set the whole order is flipped (so `--top` then surfaces the
/// bottom of the ranking). Finally truncate to `top` if set.
List<String> _orderKeys(
  Iterable<String> keys,
  int Function(String) weight,
  String sort,
  bool reverse,
  int? top,
) {
  final out = keys.toList();
  if (sort == 'count') {
    out.sort((a, b) {
      final c = weight(b).compareTo(weight(a));
      return c != 0 ? c : a.compareTo(b);
    });
  } else {
    out.sort();
  }
  if (reverse) {
    final r = out.reversed.toList();
    out
      ..clear()
      ..addAll(r);
  }
  if (top != null && out.length > top) {
    return out.sublist(0, top);
  }
  return out;
}

/// Render a `key | count | share` table for `counts`, ordered per
/// `--sort`/`--reverse`/`--top`. `share` is `count / denom` (the filtered
/// total), so it sums to 100 % when each puzzle contributes to exactly one
/// key — `header` labels the key column.
void _renderCountTable(
  Map<String, int> counts,
  String header,
  int denom,
  _Args opts,
) {
  final keys = _orderKeys(
    counts.keys,
    (k) => counts[k]!,
    opts.sort,
    opts.reverse,
    opts.top,
  );

  final keyWidth = [
    header.length,
    ...keys.map((k) => k.length),
  ].reduce((a, b) => a > b ? a : b);
  final countWidth = [
    'count'.length,
    ...keys.map((k) => counts[k]!.toString().length),
  ].reduce((a, b) => a > b ? a : b);

  stdout.writeln(
    '${header.padRight(keyWidth)}    ${'count'.padLeft(countWidth)}    share',
  );
  stdout.writeln('${'-' * keyWidth}    ${'-' * countWidth}    -----');
  for (final k in keys) {
    final v = counts[k]!;
    final share = denom == 0 ? 0.0 : v * 100 / denom;
    stdout.writeln(
      '${k.padRight(keyWidth)}    '
      '${v.toString().padLeft(countWidth)}    '
      '${share.toStringAsFixed(1).padLeft(5)}%',
    );
  }
}

void _printTable1D(List<_Puzzle> filtered, _Args opts) {
  final counts = _aggregate(filtered, opts.groupBy);
  _renderCountTable(counts, opts.groupBy, filtered.length, opts);

  if (opts.groupBy == 'slug' && filtered.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln(
      '(slug groupings count puzzle coverage; per-row share is '
      'puzzles-containing-this-slug / total filtered, and may sum to > 100% '
      'when multi-slug puzzles are present.)',
    );
  }
}

/// One bucket-key field for `dim`. Unlike the `slug` axis (which explodes a
/// puzzle into one key per slug), the `slugs` dimension is the **whole sorted
/// set** as a single atomic label — that's the joint category equilibrium
/// does *not* track, only its marginals.
String _bucketField(_Puzzle p, String dim) {
  switch (dim) {
    case 'size':
      return _sizeKey(p);
    case 'ntypes':
      return 'ntypes=${p.slugs.length}';
    case 'slugs':
      final sorted = p.slugs.toList()..sort();
      return 'slugs=${sorted.join(',')}';
    case 'scenario':
      return 'scenario=${p.scenario}';
    case 'composition':
      return 'composition=${p.compositionKey}';
    default:
      throw ArgumentError('Unknown bucket dimension: $dim');
  }
}

/// List every distinct joint bucket — the Cartesian tuple of the chosen
/// `--buckets` dimensions actually present in the filtered corpus — with its
/// population. Each puzzle lands in exactly one bucket, so shares sum to
/// 100 %. Sorting ascending (`--reverse`) surfaces the rarest tuples.
void _printBuckets(List<_Puzzle> filtered, _Args opts) {
  final dims = opts.buckets!;
  final counts = <String, int>{};
  for (final p in filtered) {
    final key = dims.map((d) => _bucketField(p, d)).join('  ');
    counts[key] = (counts[key] ?? 0) + 1;
  }

  stdout.writeln('Distinct buckets (${dims.join(' x ')}): ${counts.length}');
  stdout.writeln('');
  _renderCountTable(counts, 'bucket', filtered.length, opts);
}

void _printCrosstab(List<_Puzzle> filtered, _Args opts) {
  final rowAxis = opts.cross![0];
  final colAxis = opts.cross![1];
  final cells = _crosstab(filtered, rowAxis, colAxis);

  // Marginals: row totals (over every column, before --top truncation) and
  // column totals (over every row). These drive both sorting and the margin
  // figures, so they must be computed on the full matrix.
  final rowTotals = <String, int>{};
  final colTotals = <String, int>{};
  for (final r in cells.keys) {
    for (final entry in cells[r]!.entries) {
      rowTotals[r] = (rowTotals[r] ?? 0) + entry.value;
      colTotals[entry.key] = (colTotals[entry.key] ?? 0) + entry.value;
    }
  }

  final rows = _orderKeys(
    cells.keys,
    (k) => rowTotals[k] ?? 0,
    opts.sort,
    opts.reverse,
    opts.top,
  );
  final cols = _orderKeys(
    colTotals.keys,
    (k) => colTotals[k] ?? 0,
    opts.sort,
    opts.reverse,
    opts.top,
  );

  int cellOf(String r, String c) => cells[r]?[c] ?? 0;

  // Each cell renders as "count (pct%)" where pct is share of the row total.
  String cellText(String r, String c) {
    final v = cellOf(r, c);
    final rt = rowTotals[r] ?? 0;
    final pct = rt == 0 ? 0.0 : v * 100 / rt;
    return '$v (${pct.toStringAsFixed(0)}%)';
  }

  // Column widths: the row-label column, then one per displayed column plus a
  // trailing "total" column.
  final rowHeader = '$rowAxis \\ $colAxis';
  final labelWidth = [
    rowHeader.length,
    'total'.length,
    ...rows.map((r) => r.length),
  ].reduce((a, b) => a > b ? a : b);

  int colWidth(String c) {
    final body = rows.map((r) => cellText(r, c).length);
    final foot = (colTotals[c] ?? 0).toString().length;
    return [c.length, foot, ...body].reduce((a, b) => a > b ? a : b);
  }

  final widths = {for (final c in cols) c: colWidth(c)};
  final totalColWidth = [
    'total'.length,
    filtered.length.toString().length,
    ...rows.map((r) => (rowTotals[r] ?? 0).toString().length),
  ].reduce((a, b) => a > b ? a : b);

  // Header row.
  final sb = StringBuffer(rowHeader.padRight(labelWidth));
  for (final c in cols) {
    sb.write('  ${c.padLeft(widths[c]!)}');
  }
  sb.write('  ${'total'.padLeft(totalColWidth)}');
  stdout.writeln(sb);

  // Separator.
  final sep = StringBuffer('-' * labelWidth);
  for (final c in cols) {
    sep.write('  ${'-' * widths[c]!}');
  }
  sep.write('  ${'-' * totalColWidth}');
  stdout.writeln(sep);

  // Body rows.
  for (final r in rows) {
    final line = StringBuffer(r.padRight(labelWidth));
    for (final c in cols) {
      line.write('  ${cellText(r, c).padLeft(widths[c]!)}');
    }
    line.write('  ${(rowTotals[r] ?? 0).toString().padLeft(totalColWidth)}');
    stdout.writeln(line);
  }

  // Footer: column totals + grand total (raw counts, no percentage).
  final foot = StringBuffer('total'.padRight(labelWidth));
  var grand = 0;
  for (final c in cols) {
    final ct = colTotals[c] ?? 0;
    grand += ct;
    foot.write('  ${ct.toString().padLeft(widths[c]!)}');
  }
  foot.write('  ${grand.toString().padLeft(totalColWidth)}');
  stdout.writeln(foot);

  final truncated =
      opts.top != null &&
      (rowTotals.length > rows.length || colTotals.length > cols.length);
  if (truncated) {
    stdout.writeln('');
    stdout.writeln(
      '(showing top ${opts.top} of ${rowTotals.length} rows and '
      '${colTotals.length} columns; "total" margins cover only the '
      'displayed cells.)',
    );
  }
  if (rowAxis == 'slug' || colAxis == 'slug') {
    stdout.writeln('');
    stdout.writeln(
      '(a slug axis counts coverage: a multi-slug puzzle lands in several '
      'cells, so the grand total can exceed ${filtered.length} filtered '
      'puzzles.)',
    );
  }
}
