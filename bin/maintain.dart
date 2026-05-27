import 'dart:io';

/// Full-corpus maintenance pipeline.
///
/// Runs the 6-step routine documented in
/// `docs/dev/collection_management.md` § "Maintenance pipeline" in
/// apply mode. Every step writes back to `assets/*.txt` directly so a
/// post-run `git diff` shows the full effect; nothing is committed.
/// Fail-fast: the first failing step aborts the remaining pipeline.
const _playableLevels = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
];

const _offCascade = ['assets/overfilled-easy.txt', 'assets/overfilled.txt'];

const _allCollections = [..._playableLevels, ..._offCascade];

const _onboardingBank = 'assets/1-easy_onboarding.txt';
const _vectorCsv = 'puzzle_vectors.csv';

class StepResult {
  final String name;
  final Duration duration;
  final bool ok;
  final String? error;
  final List<String> notes;
  StepResult({
    required this.name,
    required this.duration,
    required this.ok,
    this.error,
    this.notes = const [],
  });
}

int _countLines(String path) {
  final f = File(path);
  if (!f.existsSync()) return 0;
  return f.readAsLinesSync().where((l) => l.trim().isNotEmpty).length;
}

Map<String, int> _snapshot(Iterable<String> files) {
  return {for (final f in files) f: _countLines(f)};
}

/// Run a sub-script with stdio inherited so the live output reaches
/// the user's terminal exactly as if they invoked the tool by hand.
/// Returns the exit code.
Future<int> _runScript(String script, List<String> args) async {
  stderr.writeln('  \$ dart run $script ${args.join(' ')}');
  final proc = await Process.start('dart', [
    'run',
    script,
    ...args,
  ], mode: ProcessStartMode.inheritStdio);
  return proc.exitCode;
}

/// Move `<path><suffix>` over `<path>` if the staging file exists.
/// Used to apply the `.tmp` / `.deduped` / `.cleanup` outputs the
/// sub-scripts produce.
bool _applyStaging(String path, String suffix) {
  final src = File('$path$suffix');
  if (!src.existsSync()) return false;
  final dst = File(path);
  if (dst.existsSync()) dst.deleteSync();
  src.renameSync(path);
  return true;
}

/// Delete pre-existing staging files so the run starts on a clean
/// slate. `recompute --route` is idempotent against existing `.tmp`
/// files (it would resume from them), which would mask a stale state
/// from an aborted previous run.
void _clearStaging(String suffix, Iterable<String> paths) {
  for (final p in paths) {
    final f = File('$p$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}

// ─── Step 1: recompute --route ─────────────────────────────────────

Future<StepResult> _stepRecompute() async {
  stderr.writeln('\n━━━ STEP 1/6: recompute --route ━━━');
  final sw = Stopwatch()..start();

  _clearStaging('.tmp', _allCollections);
  final code = await _runScript('bin/recompute.dart', ['--route', '-v']);
  if (code != 0) {
    sw.stop();
    return StepResult(
      name: 'recompute --route',
      duration: sw.elapsed,
      ok: false,
      error: 'exit $code',
    );
  }

  final moved = <String>[];
  for (final f in _allCollections) {
    if (_applyStaging(f, '.tmp')) moved.add(f);
  }

  sw.stop();
  return StepResult(
    name: 'recompute --route',
    duration: sw.elapsed,
    ok: true,
    notes: ['applied: ${moved.length} files'],
  );
}

// ─── Step 2: dedup_puzzles per collection ──────────────────────────

Future<StepResult> _stepDedup() async {
  stderr.writeln('\n━━━ STEP 2/6: dedup_puzzles ━━━');
  final sw = Stopwatch()..start();
  final notes = <String>[];

  for (final f in _allCollections) {
    if (!File(f).existsSync()) continue;
    final code = await _runScript('bin/dedup_puzzles.dart', [
      '-o',
      '$f.deduped',
      f,
    ]);
    if (code != 0) {
      sw.stop();
      return StepResult(
        name: 'dedup_puzzles',
        duration: sw.elapsed,
        ok: false,
        error: '$f: exit $code',
      );
    }
    final applied = _applyStaging(f, '.deduped');
    if (applied) notes.add('deduped $f');
  }

  sw.stop();
  return StepResult(
    name: 'dedup_puzzles',
    duration: sw.elapsed,
    ok: true,
    notes: notes,
  );
}

// ─── Step 3: cleanup_collections --apply ───────────────────────────

Future<StepResult> _stepCleanup() async {
  stderr.writeln('\n━━━ STEP 3/6: cleanup_collections --apply ━━━');
  final sw = Stopwatch()..start();

  _clearStaging('.cleanup', _allCollections);
  final code = await _runScript('bin/cleanup_collections.dart', [
    '--apply',
    '-v',
  ]);
  if (code != 0) {
    sw.stop();
    return StepResult(
      name: 'cleanup_collections',
      duration: sw.elapsed,
      ok: false,
      error: 'exit $code',
    );
  }

  final moved = <String>[];
  for (final f in _allCollections) {
    if (_applyStaging(f, '.cleanup')) moved.add(f);
  }

  sw.stop();
  return StepResult(
    name: 'cleanup_collections',
    duration: sw.elapsed,
    ok: true,
    notes: ['applied: ${moved.length} files'],
  );
}

// ─── Step 4: vectorize_puzzles ─────────────────────────────────────

Future<StepResult> _stepVectorize() async {
  stderr.writeln('\n━━━ STEP 4/6: vectorize_puzzles ━━━');
  final sw = Stopwatch()..start();
  final code = await _runScript('bin/vectorize_puzzles.dart', ['-v']);
  sw.stop();
  if (code != 0) {
    return StepResult(
      name: 'vectorize_puzzles',
      duration: sw.elapsed,
      ok: false,
      error: 'exit $code',
    );
  }
  final rows = _countLines(_vectorCsv);
  return StepResult(
    name: 'vectorize_puzzles',
    duration: sw.elapsed,
    ok: true,
    notes: ['$_vectorCsv: $rows rows'],
  );
}

// ─── Step 5: cluster_puzzles --apply ───────────────────────────────

Future<StepResult> _stepCluster() async {
  stderr.writeln('\n━━━ STEP 5/6: cluster_puzzles --apply ━━━');
  final sw = Stopwatch()..start();

  _clearStaging('.cleanup', _allCollections);
  final code = await _runScript('bin/cluster_puzzles.dart', [
    '--apply',
    '--max-distance',
    '0.15',
    '--keep-per-cluster',
    '1',
    '--protect-from',
    _onboardingBank,
    '-v',
  ]);
  if (code != 0) {
    sw.stop();
    return StepResult(
      name: 'cluster_puzzles --apply',
      duration: sw.elapsed,
      ok: false,
      error: 'exit $code',
    );
  }

  final moved = <String>[];
  for (final f in _allCollections) {
    if (_applyStaging(f, '.cleanup')) moved.add(f);
  }

  sw.stop();
  return StepResult(
    name: 'cluster_puzzles --apply',
    duration: sw.elapsed,
    ok: true,
    notes: ['applied: ${moved.length} files'],
  );
}

// ─── Step 6: extract_onboarding ────────────────────────────────────

Future<StepResult> _stepOnboarding() async {
  stderr.writeln('\n━━━ STEP 6/6: extract_onboarding ━━━');
  final sw = Stopwatch()..start();
  final code = await _runScript('bin/extract_onboarding.dart', [
    '--per-phase',
    '300',
    '--output',
    _onboardingBank,
    '-v',
  ]);
  sw.stop();
  if (code != 0) {
    return StepResult(
      name: 'extract_onboarding',
      duration: sw.elapsed,
      ok: false,
      error: 'exit $code',
    );
  }
  final count = _countLines(_onboardingBank);
  return StepResult(
    name: 'extract_onboarding',
    duration: sw.elapsed,
    ok: true,
    notes: ['$_onboardingBank: $count lines'],
  );
}

// ─── Summary report ────────────────────────────────────────────────

String _fmtDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  final m = d.inMinutes;
  final s = d.inSeconds - m * 60;
  return '${m}m${s.toString().padLeft(2, '0')}s';
}

void _printSummary(
  List<StepResult> results,
  Map<String, int> before,
  Map<String, int> after,
) {
  print('');
  print('═' * 72);
  print('Maintenance summary');
  print('═' * 72);

  for (final r in results) {
    final status = r.ok ? 'OK  ' : 'FAIL';
    print('[$status] ${r.name.padRight(28)} ${_fmtDuration(r.duration)}');
    if (r.error != null) print('       ! ${r.error}');
    for (final n in r.notes) {
      print('       · $n');
    }
  }

  print('');
  print('File line counts (before → after):');
  final tracked = [..._allCollections, _onboardingBank, _vectorCsv];
  for (final f in tracked) {
    final b = before[f] ?? 0;
    final a = after[f] ?? 0;
    if (b == 0 && a == 0) continue;
    final diff = a - b;
    final delta = diff == 0 ? '=' : (diff > 0 ? '+$diff' : '$diff');
    print('  ${f.padRight(34)} $b → $a  ($delta)');
  }

  final total = results.fold<Duration>(
    Duration.zero,
    (acc, r) => acc + r.duration,
  );
  print('');
  print('Total wall time: ${_fmtDuration(total)}');
}

// ─── Entry point ───────────────────────────────────────────────────

const _usage = '''
Usage: dart run bin/maintain.dart [-h]

Run the full corpus maintenance pipeline in apply mode (each step
writes back to assets/*.txt directly — inspect via `git diff` before
committing). Fail-fast: the first failing step aborts the rest.

Pipeline:
  1. recompute --route      Refresh stored cplx, re-sort constraints,
                            re-route each puzzle to its classified level.
  2. dedup_puzzles          Drop exact-duplicate puzzles per file
                            (defence-in-depth — --route already enforces).
  3. cleanup_collections    Drop disliked + boring (≥90 % trivial-FM) +
                            overlapping-MJ-border puzzles (--apply mode).
  4. vectorize_puzzles      Refresh puzzle_vectors.csv from the cleaned
                            corpus.
  5. cluster_puzzles        --apply with --max-distance 0.15 and
                            --keep-per-cluster 1, protecting the current
                            onboarding bank.
  6. extract_onboarding     Refresh assets/1-easy_onboarding.txt
                            (300 puzzles per phase) from the post-
                            cleanup corpus.

Options:
  -h, --help   Show this help.
''';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    print(_usage);
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln('Unknown arguments: ${args.join(' ')}');
    stderr.writeln(_usage);
    exit(64);
  }

  final tracked = [..._allCollections, _onboardingBank, _vectorCsv];
  final before = _snapshot(tracked);

  final steps = <Future<StepResult> Function()>[
    _stepRecompute,
    _stepDedup,
    _stepCleanup,
    _stepVectorize,
    _stepCluster,
    _stepOnboarding,
  ];

  final results = <StepResult>[];
  for (final step in steps) {
    final r = await step();
    results.add(r);
    if (!r.ok) {
      stderr.writeln('\nStep "${r.name}" failed (${r.error}). Aborting.');
      break;
    }
  }

  final after = _snapshot(tracked);
  _printSummary(results, before, after);

  exit(results.any((r) => !r.ok) ? 1 : 0);
}
