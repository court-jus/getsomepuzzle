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
    required this.success,
    required this.rejectReason,
    required this.durationMs,
    required this.puzzleLevelIndex,
    required this.puzzleLine,
  });
}
