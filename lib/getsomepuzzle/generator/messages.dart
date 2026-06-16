import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';

/// Message types sent from the worker to the UI or CLI.
sealed class GeneratorMessage {}

class GeneratorProgressMessage extends GeneratorMessage {
  final GeneratorProgress progress;
  GeneratorProgressMessage(this.progress);
}

class GeneratorPuzzleMessage extends GeneratorMessage {
  final String puzzleLine;

  /// Difficulty palier as classified by the generator's own
  /// `solveExplained` trace — the same trace it used to validate
  /// deductive uniqueness, so this comes for free.
  final PuzzleLevel level;
  GeneratorPuzzleMessage(this.puzzleLine, this.level);
}

/// Emitted whenever a worker picks a new equilibrium target for the next
/// generation attempt. [label] is null when no target is being chased
/// (equilibrium disabled or no positive-gap candidate left).
class GeneratorTargetMessage extends GeneratorMessage {
  final String? label;
  GeneratorTargetMessage(this.label);
}

class GeneratorDoneMessage extends GeneratorMessage {
  final int totalGenerated;
  GeneratorDoneMessage(this.totalGenerated);
}

/// Emitted at the end of every generation attempt, success or failure.
/// Carries all the input parameters the worker chose for the attempt plus
/// the outcome, so the CLI can append one row per attempt to
/// `generator_stats.csv` for offline analysis (failure-mode mix, duration
/// distributions, behavior across generator versions, …).
class GeneratorAttemptMessage extends GeneratorMessage {
  final int workerIndex;

  /// `true` while the corpus is below the equilibrium warmup threshold —
  /// the worker uses `pickWarmupConfig` instead of `pickTarget`.
  final bool inWarmup;

  /// Stable target identifier (e.g. `slug:SY`, `ntypes:3`, `profile:pathBased`)
  /// or `null` when no target was picked (warmup, balanced equilibrium, or
  /// equilibrium disabled).
  final String? targetKey;

  final int width;
  final int height;

  /// The ntypes the attempt explicitly targets when chasing `NTypesTarget`,
  /// or the soft cap implied by `preferredSlugs.length` otherwise. `null`
  /// when no slug preference is active (iterative loop fully free).
  final int? ntypesIntended;

  final List<String> preferredSlugs;

  /// `null` means the universe is unrestricted (all registered slugs).
  final List<String>? allowedSlugs;

  /// One of `classic`, `sh`, `pathBased`, `syBased`.
  final String scenario;

  /// Colour-domain size the attempt was *asked* to generate (2 or 3).
  /// Intent, not outcome: an auto-shrunk domain-3 success still reports 3
  /// here — the blacklist reasons about what was requested, while the
  /// equilibrium stats count the emitted line.
  final int domainSize;

  final bool success;

  /// `GenerationRejectReason.name` for an aborted attempt, `'unknown'` when
  /// an exception was caught during `generateOne`, `null` on success.
  final String? rejectReason;

  final int durationMs;

  /// `PuzzleLevel.index` on success, `null` on abandon.
  final int? puzzleLevelIndex;

  /// Full v2 puzzle line on success (lets analysis join with
  /// `puzzle_vectors.csv`), `null` on abandon.
  final String? puzzleLine;

  /// Snapshot of the per-slug deficit map passed to `GeneratorConfig` for
  /// this attempt. Lets offline analysis audit which slugs were under-
  /// represented at attempt time without having to rebuild the corpus
  /// stats at that exact instant. `null` during warm-up or when equilibrium
  /// is off; slugs with zero deficit are omitted to keep the CSV column
  /// compact.
  final Map<String, double>? slugDeficitScores;

  /// Path-based per-attempt diagnostics, `null` for non-path attempts.
  /// `pathRetries`: `preFillPath` loop iterations consumed (winning attempt on
  /// success, `maxRetries` on failure); `pathRoutingCalls`: DPLL routing
  /// invocations; `pathRoutingMsMax`/`pathRoutingMsTotal`: routing wall-time;
  /// `pathPrefillMs`: total `preFillPath` time. Feed default tuning of
  /// `--routing-timeout` / `--path-retries`.
  final int? pathRetries;
  final int? pathRoutingCalls;
  final int? pathRoutingMsMax;
  final int? pathRoutingMsTotal;
  final int? pathPrefillMs;

  /// Largest wall-clock gap (ms) between two consecutive constraint accepts
  /// in the iterative loop (counting setup-to-first-accept). For a successful
  /// attempt this is the peak the no-progress watchdog counter reached, so the
  /// distribution across successes is the safe floor for lowering `maxStall`.
  /// Null when no accept happened (e.g. prefill-stage failures).
  final int? maxAcceptGapMs;

  GeneratorAttemptMessage({
    required this.workerIndex,
    required this.inWarmup,
    required this.targetKey,
    required this.width,
    required this.height,
    required this.ntypesIntended,
    required this.preferredSlugs,
    required this.allowedSlugs,
    required this.scenario,
    this.domainSize = 2,
    required this.success,
    required this.rejectReason,
    required this.durationMs,
    required this.puzzleLevelIndex,
    required this.puzzleLine,
    this.slugDeficitScores,
    this.pathRetries,
    this.pathRoutingCalls,
    this.pathRoutingMsMax,
    this.pathRoutingMsTotal,
    this.pathPrefillMs,
    this.maxAcceptGapMs,
  });
}

/// Emitted whenever a worker's `generateOne` returns null with a
/// classifiable reason. Used by the CLI dashboard to surface why
/// attempts are failing (e.g. mostly `ratioTooHigh` → iterative loop
/// isn't picking strong-enough constraints).
class GeneratorRejectMessage extends GeneratorMessage {
  final GenerationRejectReason reason;
  GeneratorRejectMessage(this.reason);
}

/// Emitted once per `generateOne` attempt (success *or* rejection)
/// with the per-stage wall-time breakdown ([micros], microseconds)
/// AND the per-stage invocation count ([calls]). Together they let
/// the CLI dashboard compute averages like "avg µs per
/// `loop_candidate` call" — the dominant signal for "is this stage
/// worth optimising next?". Keys are stable stage names defined in
/// `PuzzleGenerator.generateOne`.
class GeneratorTimingsMessage extends GeneratorMessage {
  final Map<String, int> micros;
  final Map<String, int> calls;
  GeneratorTimingsMessage(this.micros, this.calls);
}
