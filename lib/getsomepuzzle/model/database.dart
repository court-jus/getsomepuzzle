import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter/services.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart'
    as equilibrium;
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/play_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/readiness.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/saf_access.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unicons/unicons.dart';

/// Why [Database.playlist] is empty after [Database.preparePlaylist].
/// Surfaced under the disabled Play button in `open_page` so the user
/// knows whether to import puzzles, relax filters, finish onboarding
/// puzzles already in flight, etc.
enum EmptyPlaylistReason {
  customEmpty,
  userEmpty,
  userAllPlayed,
  noPuzzlesLoaded,
  filtersTooStrict,
  generic,
}

/// Where [Database.recommendedCollectionKey] points relative to the
/// active collection's difficulty tier, used by `EndOfPlaylist` to pick
/// the suggestion caption.
enum CollectionSuggestionDirection {
  /// The recommended collection is one tier *harder* than the active
  /// one (e.g. 2-player suggested after finishing a 1-easy batch).
  up,

  /// The recommended collection is one tier *easier* than the active
  /// one (e.g. 5-expert suggested after a 6-mad batch).
  down,
}

class PuzzleData {
  String lineRepresentation = "";
  List<int> domain = [];
  int width = 0;
  int height = 0;
  int filled = 0;
  int cplx = 0;
  List<String> rules = [];

  /// [rules] as a Set, materialised once on first use. The filter predicate
  /// and the variety-gap sampler consult it per candidate per pass;
  /// allocating a fresh Set each time was pure garbage.
  late final Set<String> rulesSet = rules.toSet();

  /// User-facing scenario derived from the constraint slugs. Never
  /// serialised — recomputed on every construction via
  /// [equilibrium.detectPuzzleProfile].
  late final equilibrium.ProfileCategory userScenario;
  // True when at least one GS (group size) constraint targets size 1 — an
  // isolated cell. Such instances are trivial and not very instructive, so
  // the selection sampler demotes them while GS is being introduced during
  // onboarding (see Database.selectionTrivialGsPenalty). Computed once here
  // to avoid re-parsing the line on every filter/sampling pass.
  bool hasTrivialGroupSize = false;
  bool played = false;
  int duration = 0;
  int failures = 0;
  int hints = 0;
  // Cell-modification analytics persisted across plays. Default 0 for older
  // stats lines that pre-date the instrumentation. See Stats.recordCellEdit.
  int cellEdits = 0;
  int firstClickMs = 0;
  int longestGapMs = 0;

  /// `PuzzleLevel.index` of the collection active when this play started,
  /// or null for a non-playable collection (custom / user_* / tutorial).
  /// Persisted as the `<index>col` suffix token and consumed only by the
  /// readiness model (`readiness.dart`) — `playerLevel` ignores it.
  int? playedCollectionIndex;
  Stats? stats;
  DateTime? started;
  DateTime? finished;
  DateTime? skipped;
  int? pleasure;
  DateTime? liked;
  DateTime? disliked;

  PuzzleData(this.lineRepresentation) {
    lineRepresentation = lineRepresentation.trim();
    var attributesStr = lineRepresentation.split("_");
    final dimensions = attributesStr[2].split("x");
    domain = attributesStr[1].split("").map((e) => int.parse(e)).toList();
    width = int.parse(dimensions[0]);
    height = int.parse(dimensions[1]);
    final cells = attributesStr[3].split("").map((e) => int.parse(e)).toList();
    filled =
        (cells.where((c) => c > 0).length.toDouble() /
                cells.length.toDouble() *
                100)
            .toInt();
    final strConstraints = attributesStr[4].split(";");
    for (var strConstraint in strConstraints) {
      final parts = strConstraint.split(":");
      rules.add(parts[0]);
      // GS params are `idx.size`; the target size is the part after the
      // last dot. Size 1 means an isolated cell (trivial instance).
      if (parts[0] == 'GS' && parts.length > 1) {
        if (int.tryParse(parts[1].split(".").last) == 1) {
          hasTrivialGroupSize = true;
        }
      }
    }
    // Solution + complexity are optional trailing fields. Bare canonical
    // lines (no `v2_` prefix, no tail — see `normalizeToV2Line`) stop at
    // index 4. Match the same defensiveness as `Puzzle()` (puzzle.dart).
    cplx = attributesStr.length > 6 ? (int.tryParse(attributesStr[6]) ?? 0) : 0;
    userScenario = equilibrium.detectPuzzleProfile(lineRepresentation);
  }

  Puzzle getPuzzle() {
    return Puzzle(lineRepresentation);
  }

  String getStat() {
    final DateFormat formatter = DateFormat('yyyy-MM-ddTHH:mm:ss');
    final sld = [
      skipped != null ? "S" : "_",
      liked != null ? "L" : "_",
      disliked != null ? "D" : "_",
    ].join("");
    final String finishedForLog = finished == null
        ? "unfinished"
        : formatter.format(finished!);
    final extraFields = [
      skipped != null ? formatter.format(skipped!) : "",
      liked != null ? formatter.format(liked!) : "",
      disliked != null ? formatter.format(disliked!) : "",
      pleasure != null ? pleasure.toString() : "",
      "${hints}h",
      "${cellEdits}e",
      "${firstClickMs}fc",
      "${longestGapMs}lg",
      playedCollectionIndex == null ? "" : "${playedCollectionIndex}col",
    ].join(" - ");
    // Normalize the constraints section (sort + dedup) but keep the v2
    // grammar intact so downstream tools that parse positional fields
    // (e.g. bin/analyze_stats.dart) keep working. The runtime match key
    // is `canonicalPuzzleKey` — applied at load time, not at write time.
    final stored = normalizeV2Line(lineRepresentation);
    return "$finishedForLog ${duration}s ${failures}f $stored - $sld - $extraFields";
  }

  Puzzle begin() {
    stats = Stats();
    stats!.begin();
    started = DateTime.now();
    return getPuzzle();
  }

  void stop() {
    if (stats == null) {
      throw UnimplementedError(
        "Should never stop the time before having started it.",
      );
    }
    stats!.stop(lineRepresentation);

    played = true;
    finished = DateTime.now();
    duration = stats!.duration;
    failures = stats!.failures;
    hints = stats!.hints;
    cellEdits = stats!.cellEdits;
    firstClickMs = stats!.firstClickMs;
    longestGapMs = stats!.longestGapMs;
  }
}

class Filters {
  int minWidth;
  int maxWidth;
  int minHeight;
  int maxHeight;
  int minFilled;
  int maxFilled;
  Set<String> wantedRules;
  Set<String> bannedRules;
  Set<String> wantedFlags;
  Set<String> bannedFlags;
  Set<String> wantedDomains;
  Set<String> bannedDomains;

  /// Scenario filter: null = any scenario. Persisted via `.name`.
  equilibrium.ProfileCategory? wantedScenario;
  final log = Logger("Filters");

  /// Default value of [bannedFlags] for a fresh install or a player who
  /// never customised the filter. Exposed so widgets can compare the
  /// live filter to the default (e.g. to grey the "reset" button)
  /// without re-hardcoding the literal — a future change to the
  /// default would otherwise silently desync the UI.
  static const Set<String> defaultBannedFlags = {
    "played",
    "skipped",
    "disliked",
  };

  Filters({
    this.minWidth = 2,
    this.maxWidth = 10,
    this.minHeight = 2,
    this.maxHeight = 10,
    this.minFilled = 0,
    this.maxFilled = 100,
    this.wantedRules = const {},
    this.bannedRules = const {},
    this.wantedFlags = const {},
    this.bannedFlags = defaultBannedFlags,
    this.wantedDomains = const {},
    this.bannedDomains = const {"d3"},
  });

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      minWidth = prefs.getInt("minWidthFilter") ?? 2;
      maxWidth = prefs.getInt("maxWidthFilter") ?? 10;
      minHeight = prefs.getInt("minHeightFilter") ?? 2;
      maxHeight = prefs.getInt("maxHeightFilter") ?? 10;
      minFilled = prefs.getInt("minPrefilledFilter") ?? 0;
      maxFilled = prefs.getInt("maxPrefilledFilter") ?? 100;
      wantedRules = (prefs.getStringList("wantedRulesFilter") ?? []).toSet();
      bannedRules = (prefs.getStringList("bannedRulesFilter") ?? []).toSet();
      wantedFlags = (prefs.getStringList("wantedFlagsFilter") ?? []).toSet();
      bannedFlags =
          (prefs.getStringList("bannedFlagsFilter") ??
                  defaultBannedFlags.toList())
              .toSet();
      wantedDomains = (prefs.getStringList("wantedDomainsFilter") ?? [])
          .toSet();
      bannedDomains = (prefs.getStringList("bannedDomainsFilter") ?? ["d3"])
          .toSet();
      final scenarioStr = prefs.getString("wantedScenarioFilter");
      equilibrium.ProfileCategory? wanted;
      if (scenarioStr != null) {
        for (final p in equilibrium.ProfileCategory.values) {
          if (p.name == scenarioStr) {
            wanted = p;
            break;
          }
        }
      }
      wantedScenario = wanted;
      // Cleanup of obsolete keys (cplx filter replaced by adaptive player level).
      await prefs.remove("minCplxFilter");
      await prefs.remove("maxCplxFilter");
    } on TypeError {
      save();
    } catch (e) {
      log.severe("Error $e");
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt("minWidthFilter", minWidth);
    prefs.setInt("maxWidthFilter", maxWidth);
    prefs.setInt("minHeightFilter", minHeight);
    prefs.setInt("maxHeightFilter", maxHeight);
    prefs.setInt("minPrefilledFilter", minFilled);
    prefs.setInt("maxPrefilledFilter", maxFilled);
    prefs.setStringList("wantedRulesFilter", wantedRules.toList());
    prefs.setStringList("bannedRulesFilter", bannedRules.toList());
    prefs.setStringList("wantedFlagsFilter", wantedFlags.toList());
    prefs.setStringList("bannedFlagsFilter", bannedFlags.toList());
    prefs.setStringList("wantedDomainsFilter", wantedDomains.toList());
    prefs.setStringList("bannedDomainsFilter", bannedDomains.toList());
    if (wantedScenario != null) {
      prefs.setString("wantedScenarioFilter", wantedScenario!.name);
    } else {
      prefs.remove("wantedScenarioFilter");
    }
  }
}

/// Filter key for a puzzle's domain size — matches the `"d<n>"` slugs
/// stored in [Filters.wantedDomains] / [Filters.bannedDomains].
String domainFilterKey(int domainSize) => 'd$domainSize';

/// Recency-weighted observed distribution over the size and slug axes,
/// computed from the player's [Database.puzzles] history. Used by
/// [Database.getPuzzlesByLevel] to bias selection toward
/// under-represented categories.
///
/// `slugCounts[s]` and `sizeCounts[(w,h)]` are sums of exponentially
/// decaying weights (one weight per played puzzle). `totalPuzzles` is the
/// total weight (Σ weights), and `totalSlugUses` accumulates
/// `weight × |distinct slugs|` for each play — together they let the
/// gap formula compute `expected_share = avgK / nSlugs` exactly like
/// `_scoreAll` does in the generator.
class WeightedSelectionStats {
  final Map<String, double> slugCounts;
  final Map<(int, int), double> sizeCounts;
  final double totalPuzzles;
  final double totalSlugUses;
  final List<(int, int)> allowedSizes;
  final int nSlugs;

  const WeightedSelectionStats({
    required this.slugCounts,
    required this.sizeCounts,
    required this.totalPuzzles,
    required this.totalSlugUses,
    required this.allowedSizes,
    required this.nSlugs,
  });
}

/// Bundle of localised labels for built-in collections. Built by the
/// caller from `AppLocalizations` so `Database` stays out of the l10n
/// dependency graph.
class CollectionLabels {
  final String easy;
  final String player;
  final String advanced;
  final String strong;
  final String expert;
  final String mad;
  final String myPuzzles;
  final String recommendedTooltip;

  const CollectionLabels({
    required this.easy,
    required this.player,
    required this.advanced,
    required this.strong,
    required this.expert,
    required this.mad,
    required this.myPuzzles,
    required this.recommendedTooltip,
  });

  factory CollectionLabels.fromLocalizations(AppLocalizations loc) =>
      CollectionLabels(
        easy: loc.collectionEasy,
        player: loc.collectionPlayer,
        advanced: loc.collectionAdvanced,
        strong: loc.collectionStrong,
        expert: loc.collectionExpert,
        mad: loc.collectionMad,
        myPuzzles: loc.collectionMyPuzzles,
        recommendedTooltip: loc.tooltipRecommendedCollection,
      );

  /// Localised label for a built-in playable level collection key.
  /// Returns null for non-playable keys (custom, user_*).
  String? labelFor(String collectionKey) {
    switch (collectionKey) {
      case '1-easy':
        return easy;
      case '2-player':
        return player;
      case '3-advanced':
        return advanced;
      case '4-strong':
        return strong;
      case '5-expert':
        return expert;
      case '6-mad':
        return mad;
      default:
        return null;
    }
  }
}

class Database {
  List<PuzzleData> puzzles = [];

  /// Fallback pool for the current collection: puzzles from the matching
  /// `X-level-overfilled.txt` file. Populated by [_loadOverfilledFallback]
  /// at every [loadPuzzlesFile] call. Never mixed into [puzzles] — only
  /// consulted by [getPuzzlesByLevel] when the main pool is exhausted.
  List<PuzzleData> _overfilledPuzzles = [];

  String collection = entryCollectionKey;
  Filters currentFilters = Filters();
  bool shouldShuffle = false;
  List<PuzzleData> playlist = [];
  int playerLevel;

  /// Whether `playerLevel` is computed automatically. Readiness
  /// suggestions only make sense on top of an auto-computed level, so this
  /// gates them: a manually pinned level suppresses readiness entirely.
  /// Maintained by `main.dart` from `Settings.autoLevel`.
  bool autoLevel = false;

  /// Monotonic counter bumped by every stats mutation ([loadStats],
  /// [notePuzzleCompleted], [clearAllStats]). Invalidates the readiness
  /// cache without having to fingerprint the history on every UI rebuild.
  int _statsVersion = 0;

  int? _readinessTier;
  int _readinessStatsVersion = -1;
  ReadinessVote? _readinessVote;
  ReadinessWindow? _readinessNewestWindow;
  ReadinessWindow? _readinessPrevWindow;

  final log = Logger("Database");
  static const _builtInCollectionKeys = {
    '1-easy',
    '2-player',
    '3-advanced',
    '4-strong',
    '5-expert',
    '6-mad',
    'custom',
  };

  /// Maps each built-in level collection key to the filename of its
  /// overfilled fallback asset. Used by [_loadOverfilledFallback].
  static const _overfilledFilename = {
    '1-easy': '1-easy-overfilled.txt',
    '2-player': '2-player-overfilled.txt',
    '3-advanced': '3-advanced-overfilled.txt',
    '4-strong': '4-strong-overfilled.txt',
    '5-expert': '5-expert-overfilled.txt',
    '6-mad': '6-mad-overfilled.txt',
  };

  /// Slug of the entry-level collection — the default landing collection
  /// for new players, and the fallback target for legacy stored values
  /// like "tutorial" / "default" / "collection2" / "collection3" that no
  /// longer exist post-merge.
  static const entryCollectionKey = '1-easy';

  /// Lazy-loaded cache: canonical puzzle key → collection key for built-in
  /// collections. Built by [getCollectionLookup] and reused across calls.
  Map<String, String>? _puzzleCollectionCache;

  /// Full play history across all collections, parsed once at startup
  /// (or after import/clear) and reused by [getAllStats], [writeStats],
  /// and the stats page. Avoids re-reading and re-parsing stats files
  /// from disk on every puzzle transition or stats-page open.
  List<StatEntry> _allStats = [];

  /// Load every built-in collection file and build a map from
  /// [canonicalPuzzleKey] to the collection key (e.g. `'1-easy'`).
  /// Used by the stats dashboard to group plays by collection.
  /// [rootBundle.loadString] is non-blocking.
  Future<Map<String, String>> getCollectionLookup() async {
    if (_puzzleCollectionCache != null) return _puzzleCollectionCache!;
    _puzzleCollectionCache = {};
    for (final key in _builtInCollectionKeys) {
      if (key == 'custom') continue;
      try {
        final content = await rootBundle.loadString('assets/$key.txt');
        for (final line in content.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          _puzzleCollectionCache![identityKey(trimmed)] = key;
        }
      } catch (_) {}
    }
    return _puzzleCollectionCache!;
  }

  /// Per-constraint mastery tracker. Populated by [loadStats] from the
  /// player's history (so reinstalls or device transfers reconstruct
  /// the map from stats alone) and consulted by the onboarding modal.
  /// Optional: when null, no first-seen recording happens — callers
  /// that don't need the onboarding flow (CLI tools, tests) can skip
  /// wiring it.
  final ConstraintProgress? progress;

  /// User-chosen directory for stats file sync. When non-null,
  /// [writeStats] and [importStats] write here instead of the legacy
  /// `ApplicationDocumentsDirectory/getsomepuzzle/`. Reads still scan
  /// both locations so existing local stats are never lost.
  /// Set by [main.dart] from [Settings.statsDirectory].
  String? statsDirectory;

  /// Error description when [statsDirectory] is set but inaccessible.
  /// Set by [validateStatsDirectory], [writeStats] or
  /// [_readRawStatsFromStorage] when a file operation fails.
  /// Checked by the UI to display a warning in the settings page.
  String? statsDirectoryError;

  Database({required this.playerLevel, this.progress});

  /// Check whether [statsDirectory] is actually writable.
  /// Returns true when the path is null or passes a test write.
  /// On failure sets [statsDirectoryError] and returns false.
  Future<bool> validateStatsDirectory() async {
    final dir = statsDirectory;
    if (dir == null) {
      statsDirectoryError = null;
      return true;
    }
    try {
      await SafAccess.writeFile(dir, '.gsp_validate', 'ok');
      await SafAccess.deleteFiles(dir, '.gsp_validate');
      statsDirectoryError = null;
      return true;
    } on Exception catch (e) {
      statsDirectoryError = '$e';
      return false;
    }
  }

  /// Clear [statsDirectory] and [statsDirectoryError], flushing
  /// the merged history to the legacy location first.
  Future<void> clearStatsDirectory() async {
    await writeStatsToDefaultLocation();
    statsDirectory = null;
    statsDirectoryError = null;
  }

  void setPlayerLevel(int newLevel) {
    playerLevel = newLevel;
  }

  List<String> userPlaylistNames = [];

  /// Order matters: the dropdown is rendered in this exact sequence,
  /// so the player progresses naturally through the six difficulty
  /// paliers, then to their own playlists.
  ///
  /// Icons follow a cognitive progression — smile (easy & friendly) →
  /// brain (start to think) → graduation cap (advanced knowledge) →
  /// medal (distinction) → trophy (achievement) → fire (extreme).
  List<(String, Widget)> getCollections(
    CollectionLabels labels, {
    String? recommendedKey,
  }) => [
    for (final (key, label, icon) in [
      ('1-easy', labels.easy, UniconsLine.smile),
      ('2-player', labels.player, UniconsLine.brain),
      ('3-advanced', labels.advanced, UniconsLine.graduation_cap),
      ('4-strong', labels.strong, UniconsLine.medal),
      ('5-expert', labels.expert, UniconsLine.trophy),
      ('6-mad', labels.mad, UniconsLine.fire),
      ('custom', labels.myPuzzles, Icons.build),
    ])
      (
        key,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            Icon(icon),
            if (key == recommendedKey)
              Tooltip(
                message: labels.recommendedTooltip,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Colors.amber,
                  ),
                ),
              ),
          ],
        ),
      ),
    for (final name in userPlaylistNames)
      (
        'user_${slugify(name)}',
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text(name), Icon(Icons.playlist_play)],
        ),
      ),
  ];

  /// All playlist slugs available for saving puzzles (custom + user playlists).
  List<(String, String)> getWritablePlaylistOptions(String customLabel) => [
    ('custom', customLabel),
    for (final name in userPlaylistNames) ('user_${slugify(name)}', name),
  ];

  static String slugify(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

  Future<void> loadUserPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    userPlaylistNames = prefs.getStringList('user_playlists') ?? [];
  }

  Future<void> _saveUserPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_playlists', userPlaylistNames);
  }

  Future<void> createUserPlaylist(String name) async {
    if (userPlaylistNames.contains(name)) return;
    userPlaylistNames.add(name);
    await _saveUserPlaylists();
  }

  Future<void> deleteUserPlaylist(String name) async {
    userPlaylistNames.remove(name);
    await _saveUserPlaylists();
    final slug = slugify(name);
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('playlist_${slug}_puzzles');
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final filePath = p.join(
        documentsDirectory.path,
        'getsomepuzzle',
        'playlist_$slug.txt',
      );
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    }
  }

  void load(List<String> lines) {
    final parsed = <PuzzleData>[];
    var skipped = 0;
    for (final e in lines) {
      if (e.isEmpty || e.startsWith("#")) continue;
      try {
        parsed.add(PuzzleData(e));
      } catch (err) {
        // A single malformed line (e.g. a truncated `custom.txt` row from a
        // partial write) must not brick startup. Skip it, but log loudly so
        // the corruption is visible rather than silently swallowed.
        skipped++;
        if (skipped <= 3) {
          print('Database.load: skipping malformed puzzle line "$e" ($err)');
        }
      }
    }
    if (skipped > 0) {
      print('Database.load: skipped $skipped malformed puzzle line(s)');
    }
    puzzles = parsed;
  }

  /// Number of stats entries that count as "usable plays" — finished,
  /// not skipped — across the entire stats history, not just the
  /// currently loaded collection. Used by [recommendedCollectionKey] to
  /// decide whether the player has played enough overall to act on the
  /// recommendation. Reset on every [loadStats] call and incremented
  /// in-session via [notePuzzleCompleted] so the gate also clears as
  /// the player accumulates plays mid-session.
  int _globalUsablePlays = 0;

  /// Per-slug count of finished, non-skipped plays the player has
  /// completed *across every collection in their stats history*.
  /// Populated by [loadStats] (re-parses each entry's `puzzleLine`)
  /// and exposed via [playCountForSlug] for the Apprentissage page.
  /// Distinct from `puzzles.where(...)`-based counts which only see
  /// the currently loaded collection.
  final Map<String, int> _playCountBySlug = <String, int>{};

  /// Read-only access to the per-slug play counter. Returns 0 for
  /// slugs the player has never seen in any played puzzle.
  int playCountForSlug(String slug) => _playCountBySlug[slug] ?? 0;

  /// Cheap parse of the domain segment of a puzzle line: returns true
  /// iff the puzzle's domain contains the purple cell value (encoded
  /// as the integer 3). Used by [loadStats] to backfill
  /// [hasPlayedThirdColor] from history without instantiating a full
  /// [PuzzleData] per stat entry. Tolerates malformed lines silently.
  static bool _puzzleLineHasThirdColor(String line) {
    final parts = line.split('_');
    if (parts.length < 2) return false;
    return parts[1].contains('3');
  }

  /// Count of finished, non-skipped plays attributed to the
  /// onboarding journey. Bumped via [notePuzzleCompleted] and
  /// persisted to `SharedPreferences`. Drives [currentPhase] — every
  /// 10th completion advances the player to the next onboarding phase
  /// until they graduate past the last defined phase. Reset to 0 by
  /// the "Replay onboarding" button.
  Map<String, int> onboardingCompletions = {};

  static const _onboardingCompletionsKey = 'onboardingCompletions';

  /// Timestamp at which the player most recently graduated past the
  /// last onboarding phase. Captured the first time [currentPhase]
  /// transitions to null after [notePuzzleCompleted], or eagerly by
  /// [skipOnboarding]. For pre-feature graduates (no recorded
  /// timestamp), [loadPuzzlesFile] backfills it lazily to "now" so the
  /// third-color suggestion gate has a baseline to count from. Reset
  /// by [resetOnboardingProgress].
  DateTime? onboardingCompletedAt;

  static const _onboardingCompletedAtKey = 'onboardingCompletedAt';

  /// Finished, non-skipped plays accumulated **after** the player
  /// graduated from the last onboarding phase. Distinct from
  /// [onboardingCompletions] (which stops growing at graduation) and
  /// from [_globalUsablePlays] (which includes pre-onboarding history
  /// too). Drives the third-color suggestion gate. Reset by
  /// [resetOnboardingProgress].
  int postOnboardingCompletions = 0;

  static const _postOnboardingCompletionsKey = 'postOnboardingCompletions';

  /// True once the player has finished or skipped at least one puzzle
  /// whose domain contains the purple cell value (i.e. a 3-colour
  /// puzzle). Set by [notePuzzleCompleted] for the current session and
  /// rebuilt from the stats history by [loadStats] — so reinstalls
  /// reconstruct the flag from the stats file alone. Used as a guard
  /// to avoid suggesting 3 colours to a player who already plays them.
  bool hasPlayedThirdColor = false;

  static const _hasPlayedThirdColorKey = 'hasPlayedThirdColor';

  /// True once the "try 3 colours" suggestion modal has been displayed
  /// at least once. Prevents the modal from firing again after the
  /// player has chosen "Later" — they can still opt in via the filters
  /// page. Reset by [resetOnboardingProgress] so a fresh onboarding
  /// re-arms the suggestion.
  bool thirdColorSuggestionShown = false;

  static const _thirdColorSuggestionShownKey = 'thirdColorSuggestionShown';

  /// True once the domain-3 introduction modal (option dots + paintbrush
  /// tap-mode toggle) has been displayed. Independent from
  /// [thirdColorSuggestionShown]: the suggestion *invites* the player to
  /// opt in to 3-colour puzzles, this modal *explains their UI* the first
  /// time a purple grid actually opens — whichever route got them there
  /// (the suggestion, a shared link, or the Open-page domain filters).
  /// Reset by [resetOnboardingProgress] so a fresh onboarding re-arms it.
  bool domain3IntroShown = false;

  static const _domain3IntroShownKey = 'domain3IntroShown';

  /// Onboarding phase the player is currently in. Returns null once
  /// they've graduated past the last defined phase, in which case
  /// [preparePlaylist] reverts to the regular level-based sampler.
  OnboardingPhase? get currentPhase =>
      phaseForCompletions(onboardingCompletions);

  /// In-session counter increment: bump the global play count after a
  /// non-skipped, finished puzzle. Without this, plays accumulated
  /// during the current session would never reach the recommendation
  /// gate (only the stats-file-loaded count, populated once at app
  /// start, would matter). Also bumps [onboardingCompletions] so the
  /// phase progression keeps up with live plays, and the per-slug
  /// play counter consumed by the Learning page so newly-finished
  /// puzzles appear in their tally without waiting for a stats
  /// reload.
  void notePuzzleCompleted(PuzzleData puz) {
    final oldPhase = currentPhase;
    _statsVersion++;
    _globalUsablePlays++;
    for (final slug in puz.rules.toSet()) {
      if (slug.isEmpty || slug == 'TX') continue;
      _playCountBySlug.update(slug, (v) => v + 1, ifAbsent: () => 1);
    }
    // Latch the third-colour flag on the first 3-colour play we ever
    // see (purple has integer value 3 in `PuzzleData.domain`, which
    // mirrors the v2 line format). Once true it never flips back:
    // future puzzles still in the history bear witness even after a
    // stats reload.
    if (!hasPlayedThirdColor && puz.domain.contains(3)) {
      hasPlayedThirdColor = true;
      _persistHasPlayedThirdColor();
    }
    final wasOnboarding = oldPhase != null;
    if (wasOnboarding) {
      for (final slug in puz.rules.toSet()) {
        if (slug.isEmpty || slug == 'TX') continue;
        onboardingCompletions[slug] = (onboardingCompletions[slug] ?? 0) + 1;
      }
      _persistOnboardingCompletions();
      if (currentPhase == null) {
        if (_softFilterActive) {
          _refreshSoftDiscoveryPool();
        }
        onboardingCompletedAt = DateTime.now();
        _persistOnboardingCompletedAt();
      }
    } else {
      postOnboardingCompletions++;
      _persistPostOnboardingCompletions();
      if (_softFilterActive) {
        _softPlaysSinceElectedChange++;
      }
    }
    // Keep currentFilters aligned with the onboarding recommendation.
    // Without this, the player keeps playing puzzles from the previous
    // phase even after notePuzzleCompleted advanced currentPhase, and
    // during the soft-filter phase the banned-rules set stays stale
    // after progress.noteSeen grows firstSeen.
    final reco = recommendedOnboardingFilters;
    if (reco != null &&
        (!setEquals(currentFilters.wantedRules, reco.wantedRules) ||
            !setEquals(currentFilters.bannedRules, reco.bannedRules))) {
      currentFilters.wantedRules = reco.wantedRules;
      currentFilters.bannedRules = reco.bannedRules;
      // Fire-and-forget like the _persist* helpers above: Filters.save()
      // hits SharedPreferences, which throws without a Flutter binding
      // (some unit tests exercise notePuzzleCompleted's semantics without
      // booting the app). Swallow that async error so it can't surface as
      // an unhandled rejection; a real failure just delays the filter
      // realignment to the next launch.
      currentFilters.save().catchError((_) {});
    }
  }

  Future<void> _persistOnboardingCompletions() async {
    // Defensive: SharedPreferences requires the Flutter binding to be
    // initialized. Some unit-test setups bypass that (they exercise
    // Database semantics without booting the full app), so we treat
    // persistence as best-effort. In production a real failure here
    // only means the counter resets to its last-persisted value on
    // next launch — the player perceives at most one extra puzzle in
    // the same phase.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _onboardingCompletionsKey,
        json.encode(onboardingCompletions),
      );
    } catch (e) {
      log.fine('Failed to persist onboardingCompletions: $e');
    }
  }

  Future<void> _persistOnboardingCompletedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = onboardingCompletedAt;
      if (value == null) {
        await prefs.remove(_onboardingCompletedAtKey);
      } else {
        await prefs.setString(
          _onboardingCompletedAtKey,
          value.toIso8601String(),
        );
      }
    } catch (e) {
      log.fine('Failed to persist onboardingCompletedAt: $e');
    }
  }

  Future<void> _persistPostOnboardingCompletions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _postOnboardingCompletionsKey,
        postOnboardingCompletions,
      );
    } catch (e) {
      log.fine('Failed to persist postOnboardingCompletions: $e');
    }
  }

  Future<void> _persistHasPlayedThirdColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasPlayedThirdColorKey, hasPlayedThirdColor);
    } catch (e) {
      log.fine('Failed to persist hasPlayedThirdColor: $e');
    }
  }

  Future<void> _persistThirdColorSuggestionShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _thirdColorSuggestionShownKey,
        thirdColorSuggestionShown,
      );
    } catch (e) {
      log.fine('Failed to persist thirdColorSuggestionShown: $e');
    }
  }

  Future<void> _persistDomain3IntroShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_domain3IntroShownKey, domain3IntroShown);
    } catch (e) {
      log.fine('Failed to persist domain3IntroShown: $e');
    }
  }

  /// Should the "try 3 colours" suggestion modal be shown right now?
  /// All four conditions must hold:
  /// 1. The modal hasn't been shown yet.
  /// 2. The player has never played a 3-colour puzzle.
  /// 3. The player has finished onboarding ([currentPhase] is null and
  ///    a graduation timestamp exists).
  /// 4. They've completed at least 50 plays since graduation.
  ///
  /// The 50-plays threshold matches the spec: enough plays past the
  /// last rule introduction that the player has built confidence on
  /// the 2-colour core, and is ready for a fresh challenge.
  bool shouldSuggestThirdColor() {
    final result =
        !thirdColorSuggestionShown &&
        !hasPlayedThirdColor &&
        currentPhase == null &&
        onboardingCompletedAt != null &&
        postOnboardingCompletions >= _thirdColorSuggestionThreshold;
    log.fine(
      'shouldSuggestThirdColor=$result '
      '(shown=$thirdColorSuggestionShown, '
      'playedThird=$hasPlayedThirdColor, '
      'phase=${currentPhase?.index}, '
      'onbAt=$onboardingCompletedAt, '
      'postCount=$postOnboardingCompletions/$_thirdColorSuggestionThreshold)',
    );
    return result;
  }

  static const int _thirdColorSuggestionThreshold = 50;

  /// Mark the suggestion as shown so it never fires again. Called by
  /// the modal regardless of which button the player tapped: dismissal
  /// is enough — the player has been informed.
  Future<void> noteThirdColorSuggestionShown() async {
    thirdColorSuggestionShown = true;
    await _persistThirdColorSuggestionShown();
  }

  /// Should the domain-3 introduction modal (option dots + paintbrush
  /// tap-mode toggle) be shown for the puzzle about to be played?
  /// [hasThirdColor] is that puzzle's `domain.contains(3)`.
  ///
  /// Fires on the first purple grid the player opens, but only when:
  /// - the puzzle really is domain-3;
  /// - the modal was never shown before;
  /// - no 3-colour play exists in the stats history ([hasPlayedThirdColor])
  ///   — an imported/reinstalled history proves the player has already
  ///   met the option dots and the paintbrush, so explaining them again
  ///   would be noise.
  ///
  /// Deliberately independent of onboarding state: a player can opt in to
  /// purple from the Open-page filters mid-journey, and the modal must
  /// fire the first time that grid opens regardless of phase.
  bool shouldShowDomain3Intro(bool hasThirdColor) {
    final result = hasThirdColor && !domain3IntroShown && !hasPlayedThirdColor;
    log.fine(
      'shouldShowDomain3Intro=$result '
      '(d3=$hasThirdColor, shown=$domain3IntroShown, '
      'playedThird=$hasPlayedThirdColor)',
    );
    return result;
  }

  /// Mark the domain-3 intro as shown so it never fires again. Called on
  /// dismissal regardless of how the player left the modal: the
  /// explanation has been surfaced, which is all it promises.
  Future<void> noteDomain3IntroShown() async {
    domain3IntroShown = true;
    await _persistDomain3IntroShown();
  }

  /// Reset the onboarding counter so the player re-enters phase 0.
  /// Pairs with `ConstraintProgress.clear()` for the full
  /// "Rejouer l'onboarding" workflow. Persists immediately because
  /// `loadPuzzlesFile` (typically called right after) re-reads the
  /// counter from prefs and would otherwise silently undo the reset.
  Future<void> resetOnboardingProgress() async {
    onboardingCompletions = {};
    onboardingCompletedAt = null;
    postOnboardingCompletions = 0;
    // Re-arm the third-colour suggestion so the player who chooses to
    // start over also gets a fresh chance to discover 3 colours after
    // the new graduation. [hasPlayedThirdColor] is history-derived and
    // intentionally NOT reset — it stays true if the player has any
    // 3-colour play in their stats.
    thirdColorSuggestionShown = false;
    // Same fresh-start intent for the domain-3 UI explanation: a player
    // who replays onboarding should see it again the next time a purple
    // grid opens (unless their history already proves they play purple —
    // [hasPlayedThirdColor] stays history-derived, so the gate still
    // suppresses it for anyone who has actually played a 3-colour puzzle).
    domain3IntroShown = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingFiltersAppliedKey);
    await Future.wait([
      _persistOnboardingCompletions(),
      _persistOnboardingCompletedAt(),
      _persistPostOnboardingCompletions(),
      _persistThirdColorSuggestionShown(),
      _persistDomain3IntroShown(),
    ]);
  }

  /// Push the onboarding counter past every defined phase so
  /// [currentPhase] is null on the spot. Pairs with marking every slug
  /// as seen in `ConstraintProgress` to also disable the soft-filter
  /// (cf. [_softFilterActive]) — together they fully exit the
  /// onboarding journey, while play stats stay intact. Persists the
  /// counter so a subsequent app launch (which rebuilds
  /// `onboardingCompletions` from prefs in [loadPuzzlesFile]) doesn't
  /// silently drag the player back to phase 0.
  Future<void> skipOnboarding() async {
    onboardingCompletions = {};
    for (var phase in OnboardingPhase.phases) {
      onboardingCompletions[phase.introducing] = OnboardingPhase.phaseLength;
    }
    onboardingCompletedAt ??= DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingFiltersAppliedKey);
    await Future.wait([
      _persistOnboardingCompletions(),
      _persistOnboardingCompletedAt(),
    ]);
  }

  /// Drop the rule filters (`wantedRules`/`bannedRules`) back to their
  /// empty default and persist. Called when the player leaves
  /// onboarding so the open page no longer carries the
  /// onboarding-imposed slug envelope (the last
  /// [recommendedOnboardingFilters] would otherwise stay pinned —
  /// nothing re-applies it once `reco` is null, so without this the
  /// player stays stuck wanting/banning the final onboarding slug).
  /// Size/flag filters are left untouched. Rebuilds the playlist so the
  /// widened catalog takes effect immediately.
  Future<void> resetRuleFilters() async {
    currentFilters.wantedRules = {};
    currentFilters.bannedRules = {};
    await currentFilters.save();
    preparePlaylist();
  }

  /// Mix in puzzles from `assets/1-easy-overfilled.txt` into the catalog
  /// while the player is in onboarding on the entry-level collection.
  ///
  /// Why: phases 4 (DF) and 5 (CC) — and likely later phases — are
  /// extremely thin in `1-easy` because the generator naturally
  /// produces simple-rule, small-grid puzzles with high prefill (they
  /// classify as `overfilled` even when their solving trace is
  /// beginner-level). `1-easy-overfilled.txt` holds exactly those
  /// puzzles: `overfilled` by prefill ratio, `beginner` by trace
  /// shape — pedagogically appropriate for onboarding (high prefill
  /// = the rule does most of the work).
  ///
  /// The split is decided at generation time by `classifyTrace`
  /// (cf. `lib/getsomepuzzle/level.dart`), so the runtime doesn't
  /// have to second-guess
  /// classification on every load — anything in `1-easy-overfilled.txt`
  /// has been pre-filtered.
  ///
  /// Once the player graduates past the last defined phase
  /// (`currentPhase == null`) the augmentation stops on the next
  /// `loadPuzzlesFile`, so the regular post-onboarding catalog never
  /// sees these puzzles.
  Future<void> _augmentWithOverfilledIfOnboarding() async {
    if (currentPhase == null) return;
    if (collection != entryCollectionKey) return;
    String content;
    try {
      content = await rootBundle.loadString('assets/1-easy-overfilled.txt');
    } catch (e) {
      log.fine(
        '1-easy-overfilled.txt missing, skipping onboarding augmentation: $e',
      );
      return;
    }
    int added = 0;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      try {
        puzzles.add(PuzzleData(trimmed));
        added++;
      } catch (_) {
        // Skip malformed lines; the entry-level catalog already
        // covers the player.
      }
    }
    log.fine(
      'Augmented onboarding catalog with $added 1-easy-overfilled puzzles',
    );
  }

  /// Load the overfilled fallback pool for the current collection.
  /// Called at every [loadPuzzlesFile] so [_overfilledPuzzles] is always
  /// in sync with [collection].
  ///
  /// The pool is left empty when:
  /// - the collection has no overfilled mirror (custom, user_*, etc.)
  /// - we are in the onboarding phase of `1-easy` (the mirror is already
  ///   mixed into [puzzles] by [_augmentWithOverfilledIfOnboarding])
  Future<void> _loadOverfilledFallback() async {
    _overfilledPuzzles = [];
    final filename = _overfilledFilename[collection];
    if (filename == null) return;
    if (collection == entryCollectionKey && currentPhase != null) return;
    try {
      final content = await rootBundle.loadString('assets/$filename');
      for (final line in content.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        try {
          _overfilledPuzzles.add(PuzzleData(t));
        } catch (_) {}
      }
      log.fine(
        'Loaded ${_overfilledPuzzles.length} overfilled fallback puzzles '
        'from $filename',
      );
    } catch (_) {
      // Asset absent (new collection not yet populated) — no fallback.
    }
  }

  /// Axe B (soft-discovery widening): when the player has cleared the strict
  /// phases but not yet met every rule, pre-load a bounded pool of puzzles
  /// carrying a post-strict slug from the **next** level collection(s) up
  /// (see [softDiscoveryMaxLevelsAbove]). The soft slugs (`RT`, `SY`, …) are
  /// scarce in the entry catalog; this pool gives [getPuzzlesByLevel]
  /// somewhere to draw the elected rule from so onboarding can complete
  /// without forcing the player to switch collections by hand — while staying
  /// close to the entry difficulty. No-op outside the soft-filter phase.
  Future<void> _refreshSoftDiscoveryPool() async {
    _softDiscoveryPool = [];
    if (!_softFilterActive) return;
    final currentLevel = playableCollectionKeyToLevel[collection];
    if (currentLevel == null) return; // custom / user playlists: skip
    final softSlugs = OnboardingPhase.postStrictDiscoveryOrder.toSet();
    final existing = puzzles.map((e) => e.lineRepresentation.trim()).toSet();
    final perSlug = <String, int>{};
    final seen = <String>{};
    for (final entry in playableCollectionKeyToLevel.entries) {
      final lvl = entry.value.index;
      // Only the next level(s) up: the current collection (and its
      // 1-easy-overfilled augmentation) is already in [puzzles], and we must
      // not serve a beginner a far-harder puzzle just to introduce a rule.
      if (lvl <= currentLevel.index ||
          lvl > currentLevel.index + softDiscoveryMaxLevelsAbove) {
        continue;
      }
      String content;
      try {
        content = await rootBundle.loadString('assets/${entry.key}.txt');
      } catch (_) {
        continue;
      }
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        if (existing.contains(trimmed) || !seen.add(trimmed)) continue;
        // Cheap string pre-filter: skip lines that name no soft slug before
        // paying for a full PuzzleData parse.
        if (!softSlugs.any((s) => trimmed.contains('$s:'))) continue;
        PuzzleData puz;
        try {
          puz = PuzzleData(trimmed);
        } catch (_) {
          continue;
        }
        final carried = puz.rules.toSet().intersection(softSlugs);
        if (carried.isEmpty) continue;
        // Respect the per-slug cap so a common slug can't crowd out the rest.
        if (carried.every(
          (s) => (perSlug[s] ?? 0) >= softDiscoveryPoolPerSlugCap,
        )) {
          continue;
        }
        for (final s in carried) {
          perSlug[s] = (perSlug[s] ?? 0) + 1;
        }
        _softDiscoveryPool.add(puz);
      }
    }
    log.fine(
      'Soft-discovery pool: ${_softDiscoveryPool.length} puzzles '
      'across slugs ${perSlug.keys.toList()..sort()}',
    );
  }

  /// True when [candidate] should supersede [incumbent] as the
  /// representative play of a puzzle. A finished play always beats an
  /// unfinished one; between two finished (or two unfinished) plays the
  /// later timestamp wins. ISO-8601 stamps compare correctly as strings.
  static bool _isMoreRecentPlay(StatEntry candidate, StatEntry incumbent) {
    final candFinished = candidate.finished;
    final incFinished = incumbent.finished;
    if ((candFinished != null) != (incFinished != null)) {
      return candFinished != null;
    }
    if (candFinished != null && incFinished != null) {
      return candFinished.compareTo(incFinished) > 0;
    }
    // Both unfinished: prefer the more recent skip, else keep the incumbent.
    final candSkipped = candidate.skipped;
    final incSkipped = incumbent.skipped;
    if (candSkipped != null && incSkipped != null) {
      return candSkipped.compareTo(incSkipped) > 0;
    }
    return candSkipped != null && incSkipped == null;
  }

  void loadStats(List<StatEntry> allEntries) {
    log.finest("loadStats");
    _statsVersion++;
    _allStats = allEntries;
    // Index by identity key (string-only, no Puzzle construction): old
    // stats lines that embed a stale complexity score or constraint order
    // still match the current puzzle line. The cheap `identityKey` is
    // sufficient here — rotation-invariance and constraint normalisation
    // are not needed for stats↔catalogue matching.
    // See lib/getsomepuzzle/model/canonical.dart.
    //
    // The stats file now keeps the *full* play history (multiple rows per
    // puzzle — see writeStats). Phase 1 collapses that history back to one
    // entry per puzzle (the most recent finished play) so every downstream
    // counter behaves exactly as it did when the file held a single row per
    // puzzle: we surface the latest play, not an inflated replay count.
    final Map<String, StatEntry> solvedPuzzles = {};
    for (final entry in allEntries) {
      final key = identityKey(entry.puzzleLine);
      final existing = solvedPuzzles[key];
      if (existing == null || _isMoreRecentPlay(entry, existing)) {
        solvedPuzzles[key] = entry;
      }
    }
    // Phase 2: derive counters from the per-puzzle entries (not the raw
    // history) so replays don't inflate them.
    int usablePlays = 0;
    int postOnboardingFromStats = 0;
    bool sawThirdColor = false;
    final onbAt = onboardingCompletedAt;
    _playCountBySlug.clear();
    for (final entry in solvedPuzzles.values) {
      if (entry.finished != null && entry.skipped == null) {
        usablePlays++;
        if (onbAt != null) {
          final finishedAt = DateTime.tryParse(entry.finished!);
          if (finishedAt != null && finishedAt.isAfter(onbAt)) {
            postOnboardingFromStats++;
          }
        }
        if (!sawThirdColor && _puzzleLineHasThirdColor(entry.puzzleLine)) {
          sawThirdColor = true;
        }
        final slugs = ConstraintProgress.slugsFromLine(entry.puzzleLine);
        for (final s in slugs) {
          _playCountBySlug.update(s, (v) => v + 1, ifAbsent: () => 1);
        }
        // Rebuild the constraint-progress map from history: each
        // finished, non-skipped play counts as having seen every slug
        // declared in that puzzle. `noteSeen` keeps the earliest date
        // when called multiple times on the same slug, so the order in
        // which stat lines are processed doesn't matter — we always
        // converge to the genuine first-encounter timestamp.
        final progress = this.progress;
        if (progress != null && entry.finished != null) {
          final when = DateTime.tryParse(entry.finished!);
          if (when != null) {
            for (final slug in slugs) {
              progress.noteSeen(slug, when);
            }
          }
        }
      }
    }
    _globalUsablePlays = usablePlays;
    // Synchronise hasPlayedThirdColor with the current stats history.
    // Both directions matter: the up-promote covers a reinstall that
    // wiped prefs but kept stats; the down-promote covers a stats
    // reset (or 2-only import) where a stale `true` would otherwise
    // stick around and silently disqualify the player from the
    // third-colour suggestion forever. The risk of overriding an
    // in-session true with a stale-stats false is negligible —
    // loadStats only fires at boot or after an explicit import, and
    // neither path has an unpersisted in-session 3-colour play to
    // protect.
    if (sawThirdColor != hasPlayedThirdColor) {
      hasPlayedThirdColor = sawThirdColor;
      _persistHasPlayedThirdColor();
    }
    // Backfill postOnboardingCompletions from history when the stats
    // count is higher than the live counter. This matters in two
    // scenarios: (1) the player imports a stats file from another
    // device — the import folds new history that should bump the
    // counter, and (2) the live counter was lost (e.g. wiped prefs)
    // but the stats survived. `max` semantics protect an in-session
    // counter that has been bumped past the last stats flush.
    if (onbAt != null && postOnboardingFromStats > postOnboardingCompletions) {
      postOnboardingCompletions = postOnboardingFromStats;
      _persistPostOnboardingCompletions();
    }
    log.finest("solved $solvedPuzzles");
    for (final puz in [...puzzles, ..._overfilledPuzzles]) {
      final entry = solvedPuzzles[identityKey(puz.lineRepresentation)];
      if (entry == null) continue;
      puz.played = true;
      if (entry.finished != null) {
        puz.finished = DateTime.tryParse(entry.finished!);
      }
      if (entry.skipped != null) {
        puz.skipped = DateTime.tryParse(entry.skipped!);
      }
      if (entry.liked != null) {
        puz.liked = DateTime.tryParse(entry.liked!);
      }
      if (entry.disliked != null) {
        puz.disliked = DateTime.tryParse(entry.disliked!);
      }
      puz.pleasure = entry.pleasure;
      puz.duration = entry.duration;
      puz.failures = entry.failures;
      puz.hints = entry.hints;
      // Mirror every field PuzzleData.getStat() emits, so a flush that
      // re-emits this puzzle from memory (getStats) reproduces the same
      // row instead of zeroing the click analytics of the latest play.
      puz.cellEdits = entry.cellEdits;
      puz.firstClickMs = entry.firstClickMs;
      puz.longestGapMs = entry.longestGapMs;
      puz.playedCollectionIndex = entry.collectionIndex;
    }
  }

  /// Re-read stats from storage (default directory + [statsDirectory] if set),
  /// parse them, and rebuild all derived data (play states, counters, etc.).
  ///
  /// Called at startup by [loadPuzzlesFile] and mid-session when the user
  /// changes [statsDirectory] via the settings page.
  Future<void> reloadStatsFromStorage() async {
    final rawStats = await _readRawStatsFromStorage();
    _allStats = rawStats
        .map((line) => StatEntry.parse(line))
        .whereType<StatEntry>()
        .toList();
    loadStats(_allStats);
  }

  /// Fold the onboarding progress the currently-loaded stats prove into
  /// the prefs-backed phase counter, then realign [currentFilters] with
  /// the recomputed recommendation.
  ///
  /// Why this exists: [reloadStatsFromStorage] already rebuilds
  /// `progress.firstSeen` from the history — so a player who merges
  /// another device's stats (activating / changing the stats sync
  /// directory, or importing a stats file) stops seeing new-rule
  /// dialogs for constraints they have already met — but the *phase*
  /// counter and the rule filters pinned from it are prefs-only state
  /// that nothing reconciles. A device that had only reached, say,
  /// phase 2 would stay pinned on the phase-2 rule preset (with its
  /// OpenPage "learning track" banner) even though the merged history
  /// proves the onboarding is over.
  ///
  /// Semantics:
  /// - One-directional (`max`) merge: the history can only prove
  ///   *more* onboarding progress, never less — a graduated device
  ///   that syncs a younger history keeps its state.
  /// - Counts mirror [loadStats]'s per-puzzle collapse (a puzzle played
  ///   on several distinct dates counts once), so replays do not
  ///   inflate the phase counter.
  /// - After the merge the filters are realigned exactly like the
  ///   regular progression paths: pinned to the (possibly advanced)
  ///   recommendation while onboarding continues, released via
  ///   [resetRuleFilters] when this merge is what ended the onboarding.
  ///
  /// Deliberately **not** called from [loadStats] / [loadPuzzlesFile]:
  /// the boot path must stay prefs-authoritative so "Rejouer
  /// l'onboarding" (which clears the counter while the full history
  /// stays on disk) survives the next launch. Call it only from the
  /// explicit stats-merge entry points: [importStats] and the
  /// stats-directory change handler in `main.dart`.
  ///
  /// [wasInOnboarding] must be the onboarding state **before** the
  /// reload/merge that preceded this call — the reload itself may
  /// already have flipped the soft filter off (`firstSeen` grows with
  /// the merged history), and the filter release below must trigger
  /// exactly when this merge is what ended the onboarding, not on a
  /// later call for a player who graduated long ago.
  Future<void> reconcileOnboardingWithStats({
    required bool wasInOnboarding,
  }) async {
    final oldPhase = currentPhase;
    // Count finished, non-skipped plays per declared slug over the
    // loaded history, collapsing per-puzzle exactly like loadStats does
    // (we only need distinct identity keys — the most-recent-play
    // choice of _isMoreRecentPlay is irrelevant for counting).
    final counts = <String, int>{};
    final seenPuzzles = <String>{};
    for (final entry in _allStats) {
      if (entry.finished == null || entry.skipped != null) continue;
      if (!seenPuzzles.add(identityKey(entry.puzzleLine))) continue;
      for (final slug in ConstraintProgress.slugsFromLine(entry.puzzleLine)) {
        if (slug.isEmpty || slug == 'TX') continue;
        counts.update(slug, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    var adopted = false;
    for (final entry in counts.entries) {
      final slug = entry.key;
      if (entry.value > (onboardingCompletions[slug] ?? 0)) {
        onboardingCompletions[slug] = entry.value;
        adopted = true;
      }
    }
    if (adopted) await _persistOnboardingCompletions();
    if (adopted && oldPhase != null && currentPhase == null) {
      // The merge graduated the strict phases: stamp the graduation
      // (mirrors notePuzzleCompleted) and warm the soft-discovery pool
      // when the merged history still leaves slugs unseen.
      if (onboardingCompletedAt == null) {
        onboardingCompletedAt = DateTime.now();
        await _persistOnboardingCompletedAt();
      }
      if (_softFilterActive) await _refreshSoftDiscoveryPool();
    }
    final reco = recommendedOnboardingFilters;
    if (reco != null) {
      // Still (or newly) in onboarding: re-pin the preset, mirroring
      // the boot cross-session guard and notePuzzleCompleted.
      if (!setEquals(currentFilters.wantedRules, reco.wantedRules) ||
          !setEquals(currentFilters.bannedRules, reco.bannedRules)) {
        currentFilters.wantedRules = reco.wantedRules;
        currentFilters.bannedRules = reco.bannedRules;
        await currentFilters.save();
        preparePlaylist();
      }
    } else if (wasInOnboarding) {
      // The merged history proves the onboarding is over: release the
      // onboarding-imposed slug envelope exactly like the in-session
      // graduation path does, so the player is not left stuck
      // wanting/banning their closing onboarding slug.
      await resetRuleFilters();
    }
  }

  Iterable<PuzzleData> filter() {
    final effectiveWanted = expandMergedRules(currentFilters.wantedRules);
    final effectiveBanned = expandMergedRules(currentFilters.bannedRules);
    return puzzles.where(
      (p) => _matchesFilters(p, effectiveWanted, effectiveBanned),
    );
  }

  /// Per-puzzle predicate behind [filter]. Extracted so the soft-discovery
  /// injection in [getPuzzlesByLevel] can apply the *same* flag / size /
  /// rule / domain gates to puzzles drawn from the widened pool (which are
  /// not in [puzzles]). The two merged-rule sets are hoisted by the caller
  /// — computed once per pass, not per puzzle.
  bool _matchesFilters(
    PuzzleData puz,
    Set<String> effectiveWanted,
    Set<String> effectiveBanned,
  ) {
    if (puz.played && currentFilters.bannedFlags.contains("played")) {
      return false;
    }
    if (puz.skipped != null && currentFilters.bannedFlags.contains("skipped")) {
      return false;
    }
    if (puz.liked != null && currentFilters.bannedFlags.contains("liked")) {
      return false;
    }
    if (puz.disliked != null &&
        currentFilters.bannedFlags.contains("disliked")) {
      return false;
    }

    if (!puz.played && currentFilters.wantedFlags.contains("played")) {
      return false;
    }
    if (puz.skipped == null && currentFilters.wantedFlags.contains("skipped")) {
      return false;
    }
    if (puz.liked == null && currentFilters.wantedFlags.contains("liked")) {
      return false;
    }
    if (puz.disliked == null &&
        currentFilters.wantedFlags.contains("disliked")) {
      return false;
    }

    if (puz.filled > currentFilters.maxFilled) return false;
    if (puz.filled < currentFilters.minFilled) return false;
    final w = puz.width;
    final h = puz.height;
    final minW = currentFilters.minWidth;
    final maxW = currentFilters.maxWidth;
    final minH = currentFilters.minHeight;
    final maxH = currentFilters.maxHeight;
    final fitsNormal = w >= minW && w <= maxW && h >= minH && h <= maxH;
    final fitsRotated = h >= minW && h <= maxW && w >= minH && w <= maxH;
    if (!fitsNormal && !fitsRotated) return false;
    if (effectiveWanted.isNotEmpty &&
        effectiveWanted.intersection(puz.rulesSet).length !=
            effectiveWanted.length) {
      return false;
    }
    if (effectiveBanned.isNotEmpty &&
        effectiveBanned.intersection(puz.rulesSet).isNotEmpty) {
      return false;
    }
    if (currentFilters.wantedScenario != null &&
        puz.userScenario != currentFilters.wantedScenario) {
      return false;
    }
    final domainKey = domainFilterKey(puz.domain.length);
    if (currentFilters.bannedDomains.contains(domainKey)) return false;
    if (currentFilters.wantedDomains.isNotEmpty &&
        !currentFilters.wantedDomains.contains(domainKey)) {
      return false;
    }
    return true;
  }

  Future<void> loadPuzzlesFile([String? fileToLoad]) async {
    final prefs = await SharedPreferences.getInstance();
    shouldShuffle = prefs.getBool("shouldShuffleCollection") ?? false;
    String collectionToLoad =
        fileToLoad ??
        (prefs.getString("collectionToLoad") ?? entryCollectionKey);
    final validKeys = {
      ..._builtInCollectionKeys,
      ...userPlaylistNames.map((name) => 'user_${slugify(name)}'),
    };
    if (!validKeys.contains(collectionToLoad)) {
      // Legacy stored keys ('tutorial' from before the onboarding
      // refactor, plus 'default'/'collection2'/'collection3' from the
      // pre-difficulty-split era) all redirect to the entry-level
      // collection.
      collectionToLoad = entryCollectionKey;
    }
    collection = collectionToLoad;
    prefs.setString("collectionToLoad", collection);
    try {
      final onboardingCompletionsJson =
          prefs.getString(_onboardingCompletionsKey) ?? "{}";
      final decoded =
          json.decode(onboardingCompletionsJson) as Map<String, dynamic>;
      onboardingCompletions = decoded.map((k, v) => MapEntry(k, v as int));
    } catch (error) {
      log.severe(error);
      // The user probably had this saved in the previous version
      onboardingCompletions = {};
    }
    final rawCompletedAt = prefs.getString(_onboardingCompletedAtKey);
    onboardingCompletedAt = rawCompletedAt == null
        ? null
        : DateTime.tryParse(rawCompletedAt);
    postOnboardingCompletions =
        prefs.getInt(_postOnboardingCompletionsKey) ?? 0;
    hasPlayedThirdColor = prefs.getBool(_hasPlayedThirdColorKey) ?? false;
    thirdColorSuggestionShown =
        prefs.getBool(_thirdColorSuggestionShownKey) ?? false;
    domain3IntroShown = prefs.getBool(_domain3IntroShownKey) ?? false;
    // Lazy backfill: a player who graduated before this feature shipped
    // has currentPhase == null but no recorded timestamp. Stamp "now"
    // so the 50-plays gate starts counting from their first launch on
    // this version — otherwise they'd never see the suggestion.
    if (currentPhase == null && onboardingCompletedAt == null) {
      onboardingCompletedAt = DateTime.now();
      await _persistOnboardingCompletedAt();
    }
    await loadUserPlaylists();
    String assetContent;
    if (collection == 'custom' || collection.startsWith('user_')) {
      final slug = collection == 'custom' ? 'custom' : collection.substring(5);
      assetContent = await _loadPlaylist(slug);
    } else {
      try {
        assetContent = await rootBundle.loadString('assets/$collection.txt');
      } catch (_) {
        assetContent = await rootBundle.loadString(
          'assets/$entryCollectionKey.txt',
        );
      }
    }
    load(assetContent.split("\n"));
    await _augmentWithOverfilledIfOnboarding();
    await _loadOverfilledFallback();
    await currentFilters.load();
    await reloadStatsFromStorage();
    // After `reloadStatsFromStorage` because it populates `progress.firstSeen` from
    // the play history, which the soft-filter recommendation reads.
    await maybeApplyOnboardingFilterDefaults(prefs);
    // Cross-session guard: keep filters aligned when the phase advanced
    // between sessions (e.g. the player closed the app at a phase
    // boundary). Covers both strict-phase and soft-filter modes.
    final reco = recommendedOnboardingFilters;
    if (reco != null) {
      currentFilters.wantedRules = reco.wantedRules;
      currentFilters.bannedRules = reco.bannedRules;
      await currentFilters.save();
    }
    // Session-start force: when the app opens while soft discovery is
    // active, the first prepared batch must carry the elected rule (see
    // _forceElectedNextBatch / _injectElectedSoftRule) — otherwise a
    // player who quit during a refresh stretch would restart the whole
    // softElectedInjectPeriod cadence before meeting anything new.
    _forceElectedNextBatch = _softFilterActive;
    await _refreshSoftDiscoveryPool();
    preparePlaylist();
  }

  /// SharedPreferences key gating the one-shot application of
  /// onboarding-derived filters at first launch. Cleared by
  /// [resetOnboardingProgress] and [skipOnboarding] so the next
  /// `loadPuzzlesFile` re-applies the fresh recommendation.
  static const _onboardingFiltersAppliedKey = 'onboardingFiltersApplied';

  /// Apply the onboarding filter recommendation to [currentFilters] the
  /// first time we see this player post-refactor (flag absent in prefs).
  /// Subsequent calls are no-ops so the player's manual overrides stick.
  ///
  /// Only sets the flag when a recommendation was actually applied, so a
  /// graduated player (recommendation == null) can still receive fresh
  /// filters if their state later regresses (e.g. corrupted
  /// onboardingCompletions on a subsequent launch).
  @visibleForTesting
  Future<void> maybeApplyOnboardingFilterDefaults(
    SharedPreferences prefs,
  ) async {
    if (prefs.getBool(_onboardingFiltersAppliedKey) == true) return;
    final reco = recommendedOnboardingFilters;
    if (reco != null) {
      currentFilters.wantedRules = reco.wantedRules;
      currentFilters.bannedRules = reco.bannedRules;
      await currentFilters.save();
      await prefs.setBool(_onboardingFiltersAppliedKey, true);
    }
  }

  /// Read every persisted raw stat line from disk (or `SharedPreferences`
  /// on web) — across **all** collections. Mirrors the lookup pattern used
  /// at app boot: every `stats*` key on web, every file whose path
  /// contains `…/getsomepuzzle/stats` on native. Lines are returned in
  /// whatever order the storage iteration yields them, with duplicates
  /// across files left intact — caller dedupes if needed.
  Future<List<String>> _readRawStatsFromStorage() async {
    final List<String> stats = [];
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith("stats")) {
          log.finer("Loading stats from $key");
          stats.addAll(prefs.getStringList(key) ?? const []);
        }
      }
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final defaultPath = p.join(documentsDirectory.path, "getsomepuzzle");
      final pattern = p.join(defaultPath, "stats");
      await Directory(defaultPath).create(recursive: true);
      for (final entry in Directory(defaultPath).listSync()) {
        if (entry is! File || !entry.path.contains(pattern)) continue;
        log.finer("Loading stats from ${entry.path}");
        final content = await entry.readAsString();
        stats.addAll(content.split("\n"));
      }
      // Also read from the custom sync directory when set.
      // The caller dedupes via _mergedStatHistory / loadStats.
      if (statsDirectory != null) {
        try {
          final fileNames = await SafAccess.listFileNames(
            statsDirectory!,
            "stats",
          );
          for (final name in fileNames) {
            log.finer("Loading stats from $statsDirectory/$name");
            final content = await SafAccess.readFile(statsDirectory!, name);
            stats.addAll(content.split("\n"));
          }
        } on Exception catch (e) {
          log.warning("Failed to read stats from $statsDirectory: $e");
          statsDirectoryError = '$e';
        }
      }
    }
    return stats;
  }

  /// Persist the currently-played puzzles of the active collection without
  /// erasing entries from every other collection.
  ///
  /// Why we don't just write `getStats()` verbatim: that returns only the
  /// *current* collection's played puzzles, and `stats.txt` is the only
  /// file written here. Switching collections mid-session would therefore
  /// overwrite the file with whatever the new collection has played (often
  /// zero entries — see the regression captured in `todo.md`), silently
  /// wiping every other collection's play history.
  ///
  /// Instead we read **every** existing stat line from storage (canonical
  /// stats files + any imported file), dedupe by `(canonical key, finished)`
  /// so each *distinct play* of a puzzle is kept (the full history), and
  /// overlay the current session's plays on top so they win on conflict.
  /// The result is written back to the canonical `stats.txt` (or the
  /// `"stats"` `SharedPreferences` key on web). Legacy / imported stat
  /// files are left untouched — the dedupe at load time keeps everything
  /// coherent, and the redundancy survives a `clearAllStats` because that
  /// helper deletes every `stats*` file outright.
  ///
  /// Keying on the completion timestamp (not the canonical key alone) is
  /// what preserves replays: two plays of the same puzzle have different
  /// `finished` stamps → two rows, while the flush right after a completed
  /// play re-emits it with the *same* stamp → a single row. Unfinished
  /// plays (skips, abandoned attempts) collapse to one row per puzzle and
  /// are dropped once a finished play exists for that puzzle, mirroring the
  /// old "completion replaces the attempt" behaviour and keeping the file
  /// free of noise the analysis pipeline ignores anyway.
  /// Build the deduplicated stat history shared by [writeStats] (persisted
  /// back to disk) and [getAllStats] (shown / exported in the stats page):
  /// every stored line plus the current session's plays, keyed by
  /// `(canonical key, completion stamp)` so each distinct play survives,
  /// with the lone unfinished row of a puzzle dropped once it has a
  /// finished play. The session is folded in last so it wins on conflict.
  Future<List<String>> _mergedStatHistory() async {
    // A play is identified by its completion timestamp. Unfinished plays
    // (finished == null) share a single per-puzzle slot.
    String historyKey(StatEntry entry) {
      final canonical = canonicalPuzzleKey(entry.puzzleLine);
      return '${entry.finished ?? "unfinished"}|$canonical';
    }

    final Map<String, String> byKey = {};
    for (final entry in _allStats) {
      // fullLine() (raw line when parsed) preserves the trailing metadata
      // fields — ratings, hints, click analytics, skip markers — instead of
      // re-serializing through the minimal toString(), which would drop
      // them from stats.txt on the next flush.
      byKey[historyKey(entry)] = entry.fullLine();
    }
    final fromSession = getStats();
    for (final line in fromSession) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      byKey[historyKey(entry)] = line;
    }
    // Drop the lone unfinished row of any puzzle that also has a finished
    // play: the completion supersedes the in-progress attempt / skip.
    final finishedCanonicalKeys = <String>{};
    for (final line in byKey.values) {
      final entry = StatEntry.parse(line);
      if (entry?.finished != null) {
        finishedCanonicalKeys.add(canonicalPuzzleKey(entry!.puzzleLine));
      }
    }
    byKey.removeWhere((key, line) {
      if (!key.startsWith('unfinished|')) return false;
      final entry = StatEntry.parse(line);
      if (entry == null) return false;
      return finishedCanonicalKeys.contains(
        canonicalPuzzleKey(entry.puzzleLine),
      );
    });
    return byKey.values.toList()..sort();
  }

  Future<void> writeStats() async {
    final merged = await _mergedStatHistory();
    _allStats = merged
        .map((line) => StatEntry.parse(line))
        .whereType<StatEntry>()
        .toList();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList("stats", merged);
      return;
    }
    // Custom sync directory: write there as the single source of truth.
    // The legacy directory is deliberately not written when a custom
    // directory is set, avoiding a split-brain scenario where the sync
    // tool would pick up the stale legacy file on the next sync.
    if (statsDirectory != null) {
      try {
        await SafAccess.writeFile(
          statsDirectory!,
          "stats.txt",
          merged.join("\n"),
        );
        statsDirectoryError = null;
      } on Exception catch (e) {
        log.warning("Failed to write stats to $statsDirectory: $e");
        statsDirectoryError = '$e';
      }
      return;
    }
    await _writeToLegacyDir(merged);
  }

  /// Write the merged stat history to the default
  /// `ApplicationDocumentsDirectory/getsomepuzzle/stats.txt`,
  /// regardless of the current [statsDirectory] setting.
  /// Used before clearing [statsDirectory] so no plays are orphaned.
  Future<void> writeStatsToDefaultLocation() async {
    final merged = await _mergedStatHistory();
    await _writeToLegacyDir(merged);
  }

  Future<void> _writeToLegacyDir(List<String> merged) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDirectory.path, "getsomepuzzle");
    await Directory(path).create(recursive: true);
    final filePath = p.join(path, "stats.txt");
    File(filePath).writeAsStringSync(
      merged.join("\n"),
      mode: FileMode.writeOnly,
      flush: true,
    );
  }

  Future<void> setShouldShuffle(bool newValue) async {
    shouldShuffle = newValue;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("shouldShuffleCollection", newValue);
    preparePlaylist();
  }

  /// Number of puzzles surfaced per playlist batch on the 6 built-in
  /// level collections. End-of-batch is the natural moment to surface
  /// a level-rotation suggestion — capping at 5 avoids the player going
  /// months without seeing it on collections that hold ~1k+ puzzles.
  /// Custom and user playlists are not capped.
  static const int playlistBatchSize = 5;

  bool _isPlayableLevel(String key) =>
      playableCollectionKeyToLevel.containsKey(key);

  /// `PuzzleLevel.index` of the active collection, or null when it is not
  /// a playable level (`custom`, `user_*`, tutorial). Stamped onto every
  /// play at start so the readiness model can attribute it to a tier.
  int? get activePlayableCollectionIndex =>
      playableCollectionKeyToLevel[collection]?.index;

  void preparePlaylist() {
    if (collection == 'custom' || collection.startsWith('user_')) {
      // User-curated playlists honour the full filter pipeline and the
      // shuffle toggle exactly like built-in collections — the player
      // expects an explicit FM ban or an enabled shuffle to take effect
      // here too. What stays specific to custom/user_* is the absence
      // of a batch cap (the whole playlist plays as a single flow).
      // When shuffle is off we keep the catalog order from `filter()`,
      // which itself iterates `puzzles` in insertion order — so the
      // "play in the order I imported them" contract still holds.
      final base = filter().toList();
      playlist = shouldShuffle ? (base..shuffle()) : base;
    } else {
      // Sampling Gaussien+variety is the source of truth for the
      // selection. The shuffle toggle now only reorders the resulting
      // batch — the top-N puzzles are the same whether the player asked
      // for ordered or shuffled play, so the level-adaptive contract
      // holds in both modes. Onboarding gating is no longer applied
      // here; the recommended filters in `currentFilters` (see
      // [recommendedOnboardingFilters]) do the gating via `filter()`,
      // which `getPuzzlesByLevel` already consults.
      playlist = getPuzzlesByLevel(playerLevel).toList();
      _maybeCapBatch();
      if (shouldShuffle) playlist.shuffle();
    }
    log.fine(
      "Playlist prepared with ${playlist.length} puzzles "
      "(shuffled: $shouldShuffle, capped: ${_isPlayableLevel(collection)})",
    );
  }

  /// Whether the post-strict-phase soft filter should constrain the
  /// playlist. True when the player has cleared the strict phases AND
  /// still has at least one unseen constraint slug. Once every
  /// known slug appears in `progress.firstSeen`, the filter becomes a
  /// no-op and we let the regular sampler run.
  bool get _softFilterActive {
    final p = progress;
    if (p == null) return false;
    if (currentPhase != null) return false;
    return p.firstSeen.length < OnboardingPhase.allKnownSlugs.length;
  }

  /// True iff the player is still in any onboarding state — either a
  /// strict phase (P0-P3) or the post-strict soft filter mode. Used by
  /// the UI to surface "you haven't met every rule yet" messaging at
  /// end-of-batch and to keep the Apprentissage page actionable.
  bool get isInOnboarding => currentPhase != null || _softFilterActive;

  /// Pre-set filter recommendation derived from the player's onboarding
  /// state. Null when [isInOnboarding] is false.
  ///
  /// **Strict phase**: `wantedRules = {phase.introducing}`,
  /// `bannedRules = allKnownSlugs \ phase.allowed`. Reproduces the
  /// previous `puzzleEligibleForPhase` contract exactly as a pair of
  /// slug filters that the user can inspect and override.
  ///
  /// **Soft filter**: `wantedRules = {}`,
  /// `bannedRules = (notYetSeen \ {elected})`, where `elected` is the
  /// first slug in [OnboardingPhase.postStrictDiscoveryOrder] still
  /// missing from `progress.firstSeen`. Lets puzzles with 0 new slugs
  /// pass (refresh) AND lets the elected slug surface (single new
  /// rule), while banning every other unseen slug — a faithful
  /// translation of the old soft-filter "≤1 new slug" contract into
  /// the visible-filter model.
  ///
  /// **Terminal case** (one unseen slug left): `wantedRules =
  /// {elected}`, `bannedRules = {}`. We flip from "let refresh pass"
  /// to "force the missing slug" so the open-page banner references a
  /// real chip and onboarding converges faster.
  ({Set<String> wantedRules, Set<String> bannedRules})?
  get recommendedOnboardingFilters {
    final phase = currentPhase;
    if (phase != null) return _strictPhaseRecommendation(phase);
    if (_softFilterActive) return _softFilterRecommendation();
    return null;
  }

  ({Set<String> wantedRules, Set<String> bannedRules})
  _strictPhaseRecommendation(OnboardingPhase phase) => (
    wantedRules: {phase.introducing},
    bannedRules: OnboardingPhase.allKnownSlugs.difference(phase.allowed),
  );

  /// The post-strict soft-discovery slug the player is currently meant to
  /// meet next, or null when not in the soft-filter phase. Mirrors the
  /// election in [_softFilterRecommendation] and drives the cadence-based
  /// injection in [getPuzzlesByLevel].
  String? get electedSoftSlug {
    if (currentPhase != null) return null;
    final p = progress;
    if (p == null) return null;
    for (final slug in OnboardingPhase.postStrictDiscoveryOrder) {
      if (p.isFirstTimeFor(slug)) return slug;
    }
    return null;
  }

  /// Plays served since the elected soft-discovery slug last changed (i.e.
  /// since the player last met a new rule). In-session only; a relaunch
  /// restarts the count — offset by the session-start force below, which
  /// guarantees the first batch of a fresh launch carries the elected rule.
  int _softPlaysSinceElectedChange = 0;

  /// The elected slug observed on the previous sampling pass, used to reset
  /// [_softPlaysSinceElectedChange] the moment discovery advances.
  String? _lastElectedSlug;

  /// One-shot session-start force for the soft-discovery injection. Armed by
  /// [loadPuzzlesFile] when the app opens while the soft-filter phase is
  /// active, so the first batch prepared after a restart always carries the
  /// elected rule — a player who closed the app during a long refresh
  /// stretch meets a new rule on the next launch instead of re-waiting the
  /// whole [softElectedInjectPeriod]. Cleared by [_injectElectedSoftRule] on
  /// the first pass, whether or not the elected puzzle was spliced.
  bool _forceElectedNextBatch = false;

  @visibleForTesting
  set forceElectedNextBatchForTest(bool value) =>
      _forceElectedNextBatch = value;

  /// Soft-discovery candidates pulled from the level collections *above* the
  /// current one (Axe B): puzzles carrying a post-strict slug, so a rule too
  /// scarce in the current collection still has somewhere to come from.
  /// Populated by [_refreshSoftDiscoveryPool] when the player enters the
  /// soft-filter phase; empty otherwise.
  List<PuzzleData> _softDiscoveryPool = [];

  @visibleForTesting
  set softDiscoveryPoolForTest(List<PuzzleData> pool) =>
      _softDiscoveryPool = pool;

  ({Set<String> wantedRules, Set<String> bannedRules})?
  _softFilterRecommendation() {
    final p = progress;
    if (p == null) return null;
    final unseen = <String>{};
    String? elected;
    for (final slug in OnboardingPhase.postStrictDiscoveryOrder) {
      if (!p.isFirstTimeFor(slug)) continue;
      if (elected == null) {
        elected = slug;
      } else {
        unseen.add(slug);
      }
    }
    if (elected == null) return null;
    // Terminal case: the elected slug is the only one still unseen.
    // Force it into wantedRules — leaving the reco as ({}, {}) would
    // collapse the open-page banner onto a filter set with no visible
    // chips, and the playlist would lack any pressure to surface the
    // missing slug.
    if (unseen.isEmpty) {
      return (wantedRules: <String>{elected}, bannedRules: <String>{});
    }
    return (wantedRules: <String>{}, bannedRules: unseen);
  }

  /// Classifies *why* the current [playlist] is empty, or null if it
  /// isn't. The UI uses this to explain a disabled Play button instead
  /// of just graying it out. Probes are ordered from most specific to
  /// most generic; the first matching case wins.
  EmptyPlaylistReason? get emptyPlaylistReason {
    if (playlist.isNotEmpty) return null;
    if (collection == 'custom' && puzzles.isEmpty) {
      return EmptyPlaylistReason.customEmpty;
    }
    if (collection.startsWith('user_')) {
      if (puzzles.isEmpty) return EmptyPlaylistReason.userEmpty;
      return EmptyPlaylistReason.userAllPlayed;
    }
    if (puzzles.isEmpty) {
      return EmptyPlaylistReason.noPuzzlesLoaded;
    }
    if (filter().isEmpty) {
      return EmptyPlaylistReason.filtersTooStrict;
    }
    return EmptyPlaylistReason.generic;
  }

  void _maybeCapBatch() {
    if (_isPlayableLevel(collection) && playlist.length > playlistBatchSize) {
      playlist = playlist.sublist(0, playlistBatchSize);
    }
  }

  /// True if at least one playable puzzle in the current collection's
  /// filtered catalog is not in the active [playlist] (i.e. the player
  /// can request another batch of 20). Returns false on non-playable
  /// collections (custom, user_*) since they don't use the batch
  /// concept.
  bool hasMoreCandidatesInCurrentCollection() {
    if (!_isPlayableLevel(collection)) return false;
    final inBatch = playlist.toSet();
    return filter().any((p) => !inBatch.contains(p));
  }

  /// Minimum number of usable plays needed before we surface a
  /// recommendation. Below this, [recommendedCollectionKey] returns
  /// null — the rolling-average `playerLevel` is too noisy to act on.
  ///
  /// Tied to `playlistBatchSize` so the gate clears at the first
  /// end-of-batch boundary regardless of how the constant is tuned.
  /// We never go below 3 to keep a minimum sanity floor for a brand
  /// new player on the very first puzzles of a session.
  static int get _minPlaysForRecommendation {
    final cap = playlistBatchSize;
    return cap < 3 ? 3 : cap;
  }

  /// Suggested collection key based on `playerLevel`. Returns null
  /// when:
  ///   - the player is still in a strict onboarding phase (P0-P3): a
  ///     fast learner could otherwise be invited to jump straight to
  ///     `5-expert` despite never having met half the rules. The soft
  ///     filter (post-P3) is permissive — recommendations resume there
  ///     so a player progressing nicely can still be nudged toward
  ///     their natural level.
  ///   - the player has fewer than [_minPlaysForRecommendation] usable
  ///     plays *globally* (avoid noisy onboarding suggestions). The
  ///     count comes from [_globalUsablePlays], populated from the raw
  ///     stats file in [loadStats] — counting only the
  ///     currently-loaded collection's `puzzles` would miss every play
  ///     made in another collection during a previous session, which
  ///     would suppress the badge for any returning player who just
  ///     switched collections.
  ///   - the recommendation matches the current collection (no badge
  ///     needed) *and* readiness has nothing to add.
  ///
  /// Readiness never overrides a level-based suggestion that already
  /// points up or down — the level stays the primary signal. It only
  /// closes the gap when the level is pinned on the current collection,
  /// which is the common case for base-level players (the winsor floor
  /// collapses them to `mix − 30`, so their level cannot express
  /// readiness).
  String? get recommendedCollectionKey {
    if (currentPhase != null) return null;
    if (_globalUsablePlays < _minPlaysForRecommendation) return null;

    var level = recommendedLevelFor(playerLevel);

    // Gradual progression: never suggest a jump of more than one level above
    // or below the currently played playlist. Without this clamp a fast
    // player on 1-easy could be sent straight to 6-mad. Since this getter is
    // re-evaluated at every end-of-batch, a consistently fast player still
    // climbs one tier per batch up to their natural level. The clamp lives
    // here (not in the pure `recommendedLevelFor`) because only this getter
    // knows the current collection. When the active collection is not a
    // playable level (custom/user_*/tutorial) there is no reference tier, so
    // the unclamped recommendation is kept.
    final currentLevel = playableCollectionKeyToLevel[collection];
    if (currentLevel != null) {
      final clampedIndex = level.index.clamp(
        currentLevel.index - 1,
        currentLevel.index + 1,
      );
      level = PuzzleLevel.values[clampedIndex];
    }

    var key = levelToPlayableCollectionKey[level];
    if (currentLevel != null && key == collection) {
      final vote = _readinessVoteForCurrentTier;
      if (vote != null) key = _suggestionForReadiness(vote, currentLevel);
    }
    return (key == null || key == collection) ? null : key;
  }

  /// Sustained readiness verdict for the active collection's tier, or
  /// null when readiness does not apply (not a playable tier, auto-level
  /// off, or no usable history). Cached against [_statsVersion] so the
  /// build-time callers pay for it only when the history actually moved.
  ReadinessVote? get _readinessVoteForCurrentTier {
    final tier = activePlayableCollectionIndex;
    if (tier == null || !autoLevel) return null;
    if (_readinessTier == tier && _readinessStatsVersion == _statsVersion) {
      return _readinessVote;
    }

    final samples = <ReadinessSample>[];
    for (final entry in _levelHistory()) {
      if (entry.collectionIndex != tier) continue;
      if (entry.finished == null || entry.skipped != null) continue;
      final parsed = parsePuzzleLineFields(entry.puzzleLine);
      if (parsed == null) continue;
      final finished = DateTime.tryParse(entry.finished!);
      if (finished == null) continue;
      samples.add(
        ReadinessSample(
          finished: finished,
          duration: entry.duration,
          failures: entry.failures,
          cplx: parsed.cplx,
          cells: parsed.cells,
          nCons: parsed.nCons,
          longestGapMs: entry.longestGapMs,
        ),
      );
    }

    // No next tier (mad) ⇒ infinite projection ⇒ promote can never fire.
    final nextTierSeconds = tierReferenceSeconds(tier + 1) ?? double.infinity;
    final series = evaluateReadinessSeries(
      samples,
      nextTierSeconds,
      now: DateTime.now(),
    );
    final vote = sustainedVote(series);
    _readinessTier = tier;
    _readinessStatsVersion = _statsVersion;
    _readinessVote = vote;
    _readinessNewestWindow = series.isNotEmpty ? series.first : null;
    _readinessPrevWindow = series.length > 1 ? series[1] : null;
    _logReadiness(tier, vote);
    return vote;
  }

  /// Tier move implied by a readiness [vote], or null when it moves
  /// nothing (hold/unknown, no next tier, or already at the bottom).
  String? _suggestionForReadiness(ReadinessVote vote, PuzzleLevel tier) {
    switch (vote) {
      case ReadinessVote.promote:
        final nextIndex = tier.index + 1;
        if (nextIndex >= kTierReferencePuzzles.length) return null;
        return levelToPlayableCollectionKey[PuzzleLevel.values[nextIndex]];
      case ReadinessVote.demote:
        if (tier.index == 0) return null;
        return levelToPlayableCollectionKey[PuzzleLevel.values[tier.index - 1]];
      case ReadinessVote.hold:
      case ReadinessVote.unknown:
        return null;
    }
  }

  /// One line per fresh readiness evaluation — the corpus for the next
  /// threshold re-calibration (see the "Readiness" section of
  /// `docs/dev/adapt_to_player.md`).
  void _logReadiness(int tier, ReadinessVote vote) {
    final newest = _readinessNewestWindow;
    final previous = _readinessPrevWindow;
    final suggested = _suggestionForReadiness(vote, PuzzleLevel.values[tier]);
    final med = newest == null ? "-" : newest.medianR.toStringAsFixed(2);
    final prev = previous == null ? "-" : previous.medianR.toStringAsFixed(2);
    final hard = newest == null ? "-" : newest.hardShare.toStringAsFixed(2);
    final n = newest == null ? 0 : newest.samples;
    final proj = newest == null || !newest.projectedSeconds.isFinite
        ? "-"
        : newest.projectedSeconds.toStringAsFixed(0);
    log.info(
      "readiness tier=$tier vote=${vote.name} med=$med prev=$prev "
      "hard=$hard n=$n proj=$proj level=$playerLevel "
      "suggested=${suggested ?? "-"}",
    );
  }

  /// Direction of the current cross-collection suggestion relative to
  /// the active collection's difficulty tier, or null when there is no
  /// recommendation or no tier reference to compare against.
  ///
  /// `up` when the suggested collection is one tier harder than the
  /// active one, `down` when it is one tier easier. When the active
  /// collection is not a playable level (`custom` / `user_*` /
  /// tutorial) there is no ladder position to compare with, so the
  /// result is null — `EndOfPlaylist` then falls back to the softer
  /// "try this other collection?" caption, which stays accurate for an
  /// undirected invite.
  CollectionSuggestionDirection? get recommendedCollectionDirection {
    final currentTier = playableCollectionKeyToLevel[collection];
    if (currentTier == null) return null;
    final key = recommendedCollectionKey;
    if (key == null) return null;
    final suggestedTier = playableCollectionKeyToLevel[key];
    if (suggestedTier == null) return null;
    return suggestedTier.index > currentTier.index
        ? CollectionSuggestionDirection.up
        : CollectionSuggestionDirection.down;
  }

  /// Wipe **every** persisted stat (every collection + the
  /// recency window that drives [computePlayerLevel] and the variety
  /// bias) and reset the in-memory flags on every loaded puzzle.
  /// Destructive — there is no undo. The stored player level in
  /// [Settings] is intentionally left alone (it's outside the scope of
  /// "stats").
  Future<void> clearAllStats() async {
    _statsVersion++;
    _allStats = [];
    for (final puz in puzzles) {
      puz.played = false;
      puz.finished = null;
      puz.skipped = null;
      puz.liked = null;
      puz.disliked = null;
      puz.pleasure = null;
      puz.duration = 0;
      puz.failures = 0;
      puz.hints = 0;
      puz.cellEdits = 0;
      puz.firstClickMs = 0;
      puz.longestGapMs = 0;
      puz.playedCollectionIndex = null;
      puz.stats = null;
      puz.started = null;
    }

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('stats')) {
          await prefs.remove(key);
        }
      }
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      try {
        await SafAccess.deleteFiles(
          p.join(documentsDirectory.path, 'getsomepuzzle'),
          'stats',
        );
      } on Exception catch (e) {
        log.warning('Failed to clear legacy stats: $e');
      }
      if (statsDirectory != null) {
        try {
          await SafAccess.deleteFiles(statsDirectory!, 'stats');
          statsDirectoryError = null;
        } on Exception catch (e) {
          log.warning('Failed to clear stats in custom dir: $e');
          statsDirectoryError = '$e';
        }
      }
    }

    preparePlaylist();
  }

  void removePuzzleFromPlaylist(PuzzleData puz) {
    playlist.remove(puz);
  }

  PuzzleData? next() {
    if (playlist.isEmpty) {
      log.fine("Playlist empty");
      return null;
    }
    final selection = playlist.removeAt(0);
    log.finer("${playlist.length} puzzles remaining in playlist");
    return selection;
  }

  /// Gross-AFK guard for [computePlayerLevel]: plays with a longest idle gap
  /// longer than this (5 min) are dropped instead of being read as "slow".
  static const int _levelAfkMaxGapMs = 300000;

  /// Winsorization deltas for the per-play implicit level in
  /// [computePlayerLevel]. Each `level_i` is clamped to
  /// `[max(cplx − lower, 0), cplx + upper]` before weighting so a single
  /// outlier play (e.g. a puzzle left open, whose duration clamps to
  /// 10×expected) can no longer drag the rolling average to 0. The lower
  /// bound is deliberately gentler: a novice may legitimately take long on
  /// an easy puzzle and must not be pinned at 0. The upper bound guards
  /// against the opposite outlier — implausibly fast plays of hard puzzles
  /// (random tapping + luck).
  static const int _levelWinsorLowerDelta = 30;
  static const int _levelWinsorUpperDelta = 60;

  /// Global play history for the level computation: the cached full history
  /// ([_allStats], which preserves replays as separate rows) plus the
  /// current session's plays that have not been flushed into [_allStats]
  /// yet (they land there on the [writeStats] call that follows every
  /// completed puzzle — see `main.dart` `_onPuzzleCompleted`).
  /// Deduplicated by `(canonical key, completion stamp)` — the same key
  /// [_mergedStatHistory] uses — so a play folded in from the session
  /// supersedes its older on-disk snapshot instead of double-counting it.
  List<StatEntry> _levelHistory() {
    String key(StatEntry e) =>
        '${e.finished ?? "unfinished"}|${canonicalPuzzleKey(e.puzzleLine)}';
    final byKey = <String, StatEntry>{};
    for (final entry in _allStats) {
      byKey[key(entry)] = entry;
    }
    for (final line in getStats()) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      byKey[key(entry)] = entry;
    }
    return byKey.values.toList();
  }

  /// Compute the player's implicit level (in `cplx` units) from recent plays.
  ///
  /// The sample is the **global** full play history ([_levelHistory]):
  /// every finished, non-skipped play across all collections counts, and
  /// replays of the same puzzle are separate samples. Entries with no
  /// cached complexity (`cplx <= 0`) and gross-AFK plays
  /// (`longestGapMs > 5 min`) are excluded; each `level_i` is winsorized to
  /// `[max(cplx − 30, 0), cplx + 60]` so a single outlier play can no
  /// longer drag the rolling average below zero.
  ///
  /// Returns `fallback` when there are fewer than 2 usable samples — this
  /// preserves a manually set level rather than snapping back to 0.
  int computePlayerLevel({required int fallback}) {
    final samples = _levelHistory()
        .where((e) => e.finished != null && e.skipped == null && e.duration > 0)
        .toList();
    if (samples.length < 2) {
      log.fine(
        "computePlayerLevel: only ${samples.length} usable samples, keeping stored level $fallback",
      );
      return fallback;
    }
    samples.sort((a, b) => b.finished!.compareTo(a.finished!));
    final toAnalyze = samples.take(50).toList();

    double weightedSum = 0;
    double weightTotal = 0;
    for (var i = 0; i < toAnalyze.length; i++) {
      final entry = toAnalyze[i];
      final parsed = parsePuzzleLineFields(entry.puzzleLine);
      if (parsed == null) continue;
      final cplx = parsed.cplx;
      final cells = parsed.cells;
      // Entries without a cached complexity (custom / user playlists) are
      // skipped rather than letting `level_i = −impliedCplx` drag the
      // average to 0.
      if (cplx <= 0) continue;
      // Gross-AFK plays must not be counted as "very slow".
      if (entry.longestGapMs > _levelAfkMaxGapMs) continue;
      final nCons = parsed.nCons;
      final expected = expectedDuration(cplx, cells, entry.failures, nCons);
      // Clamp duration to neutralise puzzles left open for hours and to keep
      // log() finite if the timer recorded zero somehow.
      final clampedDur = entry.duration.clamp(1, (expected * 10).round());
      // Skill inversion: when the play's duration matches the expected
      // value for its `cplx`, `level_i = cplx`. Faster than expected ⇒
      // higher implicit level; slower ⇒ lower. Derived as
      //   level_i = 2·cplx − implied_cplx_for(this duration)
      // where implied_cplx is the proper inverse of `expectedDuration`.
      final levelI = playLevel(clampedDur, cplx, cells, entry.failures, nCons)
          .clamp(
            math.max(cplx - _levelWinsorLowerDelta, 0),
            cplx + _levelWinsorUpperDelta,
          )
          .toDouble();
      // Exponential decay, half-life = 25 puzzles.
      final weight = math.pow(0.5, i / 25.0).toDouble();
      weightedSum += levelI * weight;
      weightTotal += weight;
    }
    if (weightTotal <= 0) return fallback;
    // Floor at 0 (never negative); deliberately no upper clamp — a very fast
    // player may exceed 100.
    final level = math.max(0, (weightedSum / weightTotal).round());
    log.fine("computePlayerLevel: ${toAnalyze.length} samples, level=$level");
    return level;
  }

  /// Selection bias applied on top of the player's level when picking the
  /// next puzzles. `+5` would favour puzzles slightly harder than skill
  /// (challenge mode); `-5` would favour easier ones (rest). 0 = match.
  static const int selectionOffset = 0;

  /// Standard deviation of the cplx-distance Gaussian used to weight the
  /// catalog. With σ=5, ~68 % of picks land within ±5 of the target cplx
  /// and ~95 % within ±10; puzzles further out are still occasionally
  /// proposed, which is what saves a fast-progressing player from running
  /// out of in-tier candidates.
  static const double selectionSigma = 5.0;

  /// Half-life (in plays) of the exponential decay used to build the
  /// recency-weighted observed distribution that drives the variety bias.
  /// Larger = more memory of past plays (slower variety push); smaller =
  /// forgets older plays faster (more aggressive switching). 30 keeps
  /// ~25 % weight on a puzzle played 60 plays ago, ~10 % on one played
  /// 100 plays ago. The full played history is used (no truncation) — the
  /// decay alone determines the effective window.
  static const double selectionVarietyHalfLife = 30.0;

  /// Strength of the variety multiplier applied on top of the
  /// Gaussian-on-cplx weight. Final weight = w_cplx · (1 + α · gap). With
  /// α=1.5, a candidate puzzle that fully fills a maximally
  /// underrepresented size or slug bin gets a ×2-3 boost; a candidate
  /// whose categories are already saturated by recent plays gets ×1 (no
  /// boost). Set to 0 to disable the variety bias entirely.
  static const double selectionVarietyAlpha = 1.5;

  /// Multiplier applied to the selection weight of a puzzle holding a GS of
  /// size 1 (an isolated cell), but only while the onboarding phase that
  /// introduces GS is active (`currentPhase.introducing == 'GS'`). These
  /// trivial instances teach the rule poorly, so we strongly demote them
  /// during discovery. Kept small but non-zero: they stay drawable as a last
  /// resort if no non-trivial GS puzzle is available, so the playlist never
  /// empties. Once GS is past its phase, the demotion lifts (factor 1).
  static const double selectionTrivialGsPenalty = 0.05;

  /// Post-strict soft-discovery cadence. The rules introduced after the
  /// strict phases (`OnboardingPhase.postStrictDiscoveryOrder`) are rare in
  /// the entry-level catalog and get drowned by the abundant "refresh"
  /// draws, which stalls onboarding (the elected rule never surfaces). We
  /// instead inject the elected rule's puzzle into the batch once the player
  /// has gone this many plays without meeting a new rule — targeting roughly
  /// one new rule every 10–15 plays given the 5-puzzle batch granularity,
  /// rather than every batch (too fast) or never (the stall).
  static const int softElectedInjectPeriod = 10;

  /// Below this many eligible elected-rule puzzles in the *current*
  /// collection, the injection widens its draw to the harder level
  /// collections ([_softDiscoveryPool]) so a rule that is scarce at the
  /// entry level (e.g. `RT`, `CT` in `1-easy`) still surfaces.
  static const int softElectedMinInCollection = 8;

  /// Per-slug cap when building [_softDiscoveryPool] — enough candidates to
  /// sample from without holding the whole higher-level corpus in memory.
  static const int softDiscoveryPoolPerSlugCap = 150;

  /// How many difficulty levels above the current collection the soft-
  /// discovery pool may reach. Kept at 1 so a beginner meets the rare soft
  /// rules on `2-player` puzzles, never on `6-mad` ones — the entry +
  /// next-level corpus already holds ≥ a dozen eligible puzzles for every
  /// soft slug (RT, the scarcest, has ~12).
  static const int softDiscoveryMaxLevelsAbove = 1;

  // Random source for puzzle sampling. Exposed as a package-private setter
  // so tests can pin it to a seeded Random for reproducibility.
  math.Random _samplingRandom = math.Random();
  // ignore: unused_element
  set samplingRandom(math.Random r) => _samplingRandom = r;

  /// Filtered catalog ordered by a weighted draw combining two factors:
  ///
  /// 1. **Skill match (cplx)** — Gaussian on `puzzle.cplx − (level +
  ///    selectionOffset)` with std [selectionSigma]. Keeps the bulk of
  ///    proposals near the player's level, with a long tail so a
  ///    fast-progressing player still occasionally sees harder ones.
  ///
  /// 2. **Variety bias** — multiplicative factor `(1 + α · gap)` where
  ///    `α = [selectionVarietyAlpha]` and `gap` is how
  ///    under-represented this puzzle's *size* and *slug* categories are
  ///    in the player's recency-weighted observed distribution (decay
  ///    half-life [selectionVarietyHalfLife]). Targets reuse the
  ///    generator's equilibrium shapes (`sizeRawWeight`, slug
  ///    `avgK / nSlugs`) so the offered catalog drifts toward the same
  ///    balance the corpus is generated against. A puzzle whose categories
  ///    are already saturated by recent plays gets factor ≈ 1 — so the
  ///    player can comfortably chain a few similar puzzles before the
  ///    variety bias starts pushing.
  ///
  /// Empty list ⇒ the filtered catalog itself is empty (every puzzle
  /// played / skipped / disliked, or filters too restrictive).
  ///
  /// Implementation: Efraimidis-Spirakis weighted reservoir / sort trick.
  /// Each item gets key `−ln(uniform()) / weight`; sorting ascending is
  /// equivalent to sampling without replacement proportionally to the
  /// weights.
  List<PuzzleData> getPuzzlesByLevel(int level) {
    final mu = level + selectionOffset;
    final twoSigmaSq = 2 * selectionSigma * selectionSigma;
    var filtered = filter().toList();

    // Fallback: if the main collection is exhausted (all played, skipped, or
    // filtered out), draw from the overfilled mirror — same filters apply so
    // user preferences (rule bans, dimensions, etc.) are still honoured.
    if (filtered.isEmpty && _overfilledPuzzles.isNotEmpty) {
      final effectiveWanted = expandMergedRules(currentFilters.wantedRules);
      final effectiveBanned = expandMergedRules(currentFilters.bannedRules);
      filtered = _overfilledPuzzles
          .where((p) => _matchesFilters(p, effectiveWanted, effectiveBanned))
          .toList();
    }

    if (filtered.isEmpty) return const [];
    final varietyStats = _buildRecencyWeightedStats(filtered);
    // Only demote trivial GS puzzles while GS is the rule being introduced.
    final demoteTrivialGs = currentPhase?.introducing == 'GS';
    final keyed = filtered.map((p) {
      final d = p.cplx - mu;
      // Clamp the exponent to avoid `exp` underflow producing key = +∞ for
      // every puzzle on the tail (which would then sort arbitrarily).
      final wCplx = math.exp(-math.min(d * d / twoSigmaSq, 700));
      final gap = _varietyGapForPuzzle(p, varietyStats);
      final wVariety = 1 + selectionVarietyAlpha * gap;
      var w = wCplx * wVariety;
      if (demoteTrivialGs && p.hasTrivialGroupSize) {
        w *= selectionTrivialGsPenalty;
      }
      // The +1e-300 below guards against `nextDouble() == 0`, which would
      // make `−ln(u)` infinite and corrupt the sort.
      final u = _samplingRandom.nextDouble() + 1e-300;
      final key = -math.log(u) / w;
      return (p, key);
    }).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    final result = keyed.map((e) => e.$1).toList();
    _injectElectedSoftRule(result, mu.toDouble(), twoSigmaSq);
    return result;
  }

  /// Post-strict soft-discovery injection (Axe A + B). The elected new rule
  /// is rare in the entry catalog and gets drowned by refresh draws, so left
  /// to the weighted sampler it almost never surfaces — the stall this
  /// reproduces. Instead, we splice one elected-rule puzzle into the
  /// upcoming batch when any of these holds:
  /// - the player has gone [softElectedInjectPeriod] plays without meeting a
  ///   new rule (the regular cadence);
  /// - the filtered batch is empty (terminal single-slug case);
  /// - a fresh session just opened in the soft phase
  ///   ([_forceElectedNextBatch], armed by [loadPuzzlesFile]) — the first
  ///   batch of a launch always carries the elected rule, so a player who
  ///   closed the app during a refresh stretch meets something new on the
  ///   next open instead of re-waiting the cadence.
  ///
  /// Candidates come from the current collection first and, when it is too
  /// thin ([softElectedMinInCollection]), from the widened
  /// [_softDiscoveryPool] (Axe B). No-op outside the soft phase.
  void _injectElectedSoftRule(
    List<PuzzleData> result,
    double mu,
    double twoSigmaSq,
  ) {
    final elected = electedSoftSlug;
    if (elected == null) return;
    // Reset the cadence the moment discovery advances to a new rule.
    if (elected != _lastElectedSlug) {
      _lastElectedSlug = elected;
      _softPlaysSinceElectedChange = 0;
    }
    // Session-start force: one-shot, armed by loadPuzzlesFile. The first
    // batch prepared after a restart in the soft phase must carry the
    // elected rule; if the weighted draw already put it in the upcoming
    // batch, the guarantee is met without splicing a second copy.
    final forceForSessionStart = _forceElectedNextBatch;
    _forceElectedNextBatch = false;
    if (forceForSessionStart &&
        result.take(playlistBatchSize).any((p) => p.rules.contains(elected))) {
      return;
    }
    final due =
        forceForSessionStart ||
        _softPlaysSinceElectedChange >= softElectedInjectPeriod;
    if (!due && result.isNotEmpty) return;

    final inCollection = result
        .where((p) => p.rules.contains(elected))
        .toList();
    final pool = <PuzzleData>[...inCollection];
    if (inCollection.length < softElectedMinInCollection) {
      final effectiveWanted = expandMergedRules(currentFilters.wantedRules);
      final effectiveBanned = expandMergedRules(currentFilters.bannedRules);
      pool.addAll(
        _softDiscoveryPool.where(
          (p) =>
              p.rules.contains(elected) &&
              _matchesFilters(p, effectiveWanted, effectiveBanned),
        ),
      );
    }
    if (pool.isEmpty) return; // genuine corpus gap — the test will surface it

    // Weighted pick by the same cplx-Gaussian used above.
    PuzzleData? pick;
    var bestKey = double.infinity;
    for (final p in pool) {
      final d = p.cplx - mu;
      final w = math.exp(-math.min(d * d / twoSigmaSq, 700));
      final u = _samplingRandom.nextDouble() + 1e-300;
      final key = -math.log(u) / w;
      if (key < bestKey) {
        bestKey = key;
        pick = p;
      }
    }
    if (pick == null) return;

    // Splice the elected puzzle into a random slot inside the upcoming batch
    // so it is served within the next few plays (≈ period … period+batch).
    result.remove(pick);
    final span = math.min(playlistBatchSize, result.length + 1);
    final slot = span <= 1 ? 0 : _samplingRandom.nextInt(span);
    result.insert(slot, pick);
  }

  /// Build the recency-weighted observed distribution over size and slug
  /// axes. Iterates the played history (recent-first) and applies an
  /// exponential decay with half-life [selectionVarietyHalfLife]. The
  /// universe (set of reachable slugs / sizes) is derived from
  /// [filteredCatalog] so that categories the player has filtered out (or
  /// that simply don't exist in the current collection) don't contribute
  /// phantom gaps.
  @visibleForTesting
  WeightedSelectionStats buildRecencyWeightedStats(
    Iterable<PuzzleData> filteredCatalog,
  ) => _buildRecencyWeightedStats(filteredCatalog);

  WeightedSelectionStats _buildRecencyWeightedStats(
    Iterable<PuzzleData> filteredCatalog,
  ) {
    final played =
        puzzles
            .where(
              (p) =>
                  p.played &&
                  p.finished != null &&
                  p.skipped == null &&
                  p.duration > 0,
            )
            .toList()
          ..sort((a, b) => b.finished!.compareTo(a.finished!));

    final slugCounts = <String, double>{};
    final sizeCounts = <(int, int), double>{};
    double total = 0;
    double totalSlugUses = 0;
    for (var i = 0; i < played.length; i++) {
      final p = played[i];
      final w = math.pow(0.5, i / selectionVarietyHalfLife).toDouble();
      total += w;
      // Size is orientation-agnostic: 4x5 and 5x4 share one bin, matching the
      // generator's equilibrium (see equilibrium.canonicalSize).
      final key = equilibrium.canonicalSize(p.width, p.height);
      sizeCounts[key] = (sizeCounts[key] ?? 0) + w;
      final distinct = p.rules.toSet();
      for (final s in distinct) {
        slugCounts[s] = (slugCounts[s] ?? 0) + w;
      }
      totalSlugUses += w * distinct.length;
    }

    final allowedSlugs = <String>{};
    final allowedSizes = <(int, int)>{};
    for (final p in filteredCatalog) {
      allowedSlugs.addAll(p.rules);
      allowedSizes.add(equilibrium.canonicalSize(p.width, p.height));
    }

    return WeightedSelectionStats(
      slugCounts: slugCounts,
      sizeCounts: sizeCounts,
      totalPuzzles: total,
      totalSlugUses: totalSlugUses,
      allowedSizes: allowedSizes.toList(),
      nSlugs: allowedSlugs.length,
    );
  }

  /// Variety gap for a single candidate puzzle: how much its size and
  /// slug categories are under-represented in the recency-weighted
  /// observed distribution. Returns 0 when the history is empty (gracefully
  /// degrades to the legacy cplx-only behaviour).
  ///
  /// Slug gap is averaged over the puzzle's distinct slugs (not summed) so
  /// puzzles with many constraints aren't artificially advantaged. Size
  /// gap reuses [equilibrium.sizeRawWeight] normalized over the currently
  /// reachable size set.
  @visibleForTesting
  double varietyGapForPuzzle(PuzzleData p, WeightedSelectionStats stats) =>
      _varietyGapForPuzzle(p, stats);

  double _varietyGapForPuzzle(PuzzleData p, WeightedSelectionStats stats) {
    if (stats.totalPuzzles <= 0) return 0.0;

    double slugGap = 0.0;
    final distinct = p.rulesSet;
    if (distinct.isNotEmpty && stats.nSlugs > 0) {
      final avgK = stats.totalSlugUses / stats.totalPuzzles;
      final expSlug = avgK / stats.nSlugs;
      for (final s in distinct) {
        final c = stats.slugCounts[s] ?? 0;
        final share = c / stats.totalPuzzles;
        final gap = expSlug - share;
        if (gap > 0) slugGap += gap;
      }
      slugGap /= distinct.length;
    }

    double sizeGap = 0.0;
    if (stats.allowedSizes.isNotEmpty) {
      final raw = equilibrium.sizeRawWeight(p.width, p.height);
      if (raw > 0) {
        final totalRaw = stats.allowedSizes.fold<double>(
          0.0,
          (sum, sz) => sum + equilibrium.sizeRawWeight(sz.$1, sz.$2),
        );
        final expSize = totalRaw > 0 ? raw / totalRaw : 0.0;
        final c =
            stats.sizeCounts[equilibrium.canonicalSize(p.width, p.height)] ?? 0;
        final share = c / stats.totalPuzzles;
        final gap = expSize - share;
        if (gap > 0) sizeGap = gap;
      }
    }

    return slugGap + sizeGap;
  }

  /// Whether any unplayed puzzle exists in the catalog when
  /// user-configured filters (size, rules) are ignored. Only the
  /// baseline exclusions (played / skipped / disliked) still apply.
  /// Used internally by [areFiltersBlocking] — `EndOfPlaylist` should
  /// call that getter rather than this one directly.
  bool hasUnplayedIgnoringFilters() {
    return puzzles.any(
      (p) => !p.played && p.skipped == null && p.disliked == null,
    );
  }

  /// True when user-set filters are responsible for an empty playlist:
  /// `filter()` yields nothing (so the engine cannot pick a next
  /// batch) while [hasUnplayedIgnoringFilters] confirms playable
  /// puzzles still exist. In that state `EndOfPlaylist` should invite
  /// the player to relax filters.
  ///
  /// We deliberately do **not** treat the implicit `played` ban as a
  /// "user filter": after a 20-puzzle batch, those 20 are
  /// `played=true`, but the remaining ~1000 in the collection are
  /// still picked up by `filter()` and the playlist just needs to be
  /// rebuilt — not a filter problem. Keying the message on
  /// `hasUnplayedIgnoringFilters` alone (the previous behaviour)
  /// caused the "filters hiding" message to surface at every batch
  /// boundary.
  bool get areFiltersBlocking =>
      filter().isEmpty && hasUnplayedIgnoringFilters();

  List<String> getStats() {
    return puzzles
        .where((puz) => puz.played)
        .map((puz) => puz.getStat())
        .toList();
  }

  /// Merge raw stat lines from an imported file into persistent storage,
  /// then reload the in-memory state. Only the lines that successfully
  /// parse as [StatEntry] are kept (so user-edited or corrupt files don't
  /// poison the store). Returns the number of valid entries persisted.
  ///
  /// We deliberately write to a fresh `stats_imported_<ts>.txt` rather
  /// than overwriting `stats.txt`: the next [writeStats] call would clobber
  /// `stats.txt` with only the current collection's plays, throwing away
  /// the import for every other collection. The dedicated file is picked
  /// up by [_readRawStatsFromStorage] on subsequent boots like any other
  /// stats file, and [loadStats] dedupes by canonical key so duplicates
  /// between the import and the existing store collapse harmlessly.
  Future<int> importStats(String content) async {
    // Snapshot before the merge below: loadStats may already end the
    // soft-filter phase (firstSeen grows with the imported history),
    // and reconcileOnboardingWithStats releases the onboarding filter
    // preset exactly when this import is what ended the onboarding.
    final wasInOnboarding = isInOnboarding;
    final List<String> validLines = [];
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (StatEntry.parse(line) == null) continue;
      validLines.add(line);
    }
    if (validLines.isEmpty) return 0;
    final timestamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      // SharedPreferences keys starting with "stats" are picked up by
      // _readRawStatsFromStorage — same merge semantics as the native path.
      await prefs.setStringList('stats_imported_$timestamp', validLines);
    } else {
      final targetDir =
          statsDirectory ??
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            'getsomepuzzle',
          );
      final fileName = 'stats_imported_$timestamp.txt';
      try {
        await SafAccess.writeFile(targetDir, fileName, validLines.join('\n'));
      } on Exception catch (e) {
        log.warning('Failed to write imported stats to $targetDir: $e');
        if (statsDirectory != null) statsDirectoryError = '$e';
      }
    }
    _allStats.addAll(
      validLines.map((line) => StatEntry.parse(line)).whereType<StatEntry>(),
    );
    loadStats(_allStats);
    // The import folded foreign history into the load: fold the
    // onboarding progress it proves into the phase counter and realign
    // the filters, the same way stats-directory changes do (see
    // reconcileOnboardingWithStats).
    await reconcileOnboardingWithStats(wasInOnboarding: wasInOnboarding);
    preparePlaylist();
    return validLines.length;
  }

  /// Every persisted stat line across **all** collections — the full play
  /// history, deduplicated by `(canonical key, completion stamp)` via the
  /// shared [_mergedStatHistory] (the same set [writeStats] persists). So
  /// viewing / exporting the "all" scope surfaces every play of a puzzle,
  /// not just the latest — that's the channel a mobile player uses to get
  /// their history out for analysis.
  ///
  /// In-session plays from the currently-loaded collection are folded in
  /// last so they take precedence over any older snapshot still on disk —
  /// otherwise viewing or sharing right after finishing a puzzle would
  /// surface its previous entry (or nothing) instead of the just-recorded
  /// timings.
  Future<List<String>> getAllStats() => _mergedStatHistory();

  /// All stat entries across every collection, in-memory cached form.
  /// Avoids the serialize-parse round-trip that [getAllStats] performs.
  /// Use this from the stats page; use [getAllStats] for export/share.
  List<StatEntry> getAllStatEntries() => _allStats;

  String _playlistFileName(String slug) =>
      slug == 'custom' ? 'custom.txt' : 'playlist_$slug.txt';

  String _playlistPrefsKey(String slug) =>
      slug == 'custom' ? 'custom_puzzles' : 'playlist_${slug}_puzzles';

  Future<String> _loadPlaylist(String slug) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final lines = prefs.getStringList(_playlistPrefsKey(slug)) ?? [];
      return lines.join('\n');
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final filePath = p.join(
      documentsDirectory.path,
      'getsomepuzzle',
      _playlistFileName(slug),
    );
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  /// Backward-compatible alias for addToPlaylist('custom', ...).
  Future<void> addToCustomCollection(String puzzleLine) =>
      addToPlaylist('custom', puzzleLine);

  Future<void> addToPlaylist(String collectionKey, String puzzleLine) async {
    final slug = collectionKey == 'custom'
        ? 'custom'
        : collectionKey.replaceFirst('user_', '');
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final lines = prefs.getStringList(_playlistPrefsKey(slug)) ?? [];
      lines.add(puzzleLine);
      await prefs.setStringList(_playlistPrefsKey(slug), lines);
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dirPath = p.join(documentsDirectory.path, 'getsomepuzzle');
      await Directory(dirPath).create(recursive: true);
      final filePath = p.join(dirPath, _playlistFileName(slug));
      final file = File(filePath);
      await file.writeAsString('$puzzleLine\n', mode: FileMode.append);
    }
  }

  Future<void> deleteFromPlaylist(
    String collectionKey,
    String puzzleLine,
  ) async {
    final slug = collectionKey == 'custom'
        ? 'custom'
        : collectionKey.replaceFirst('user_', '');
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final lines = prefs.getStringList(_playlistPrefsKey(slug)) ?? [];
      lines.remove(puzzleLine);
      await prefs.setStringList(_playlistPrefsKey(slug), lines);
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final filePath = p.join(
        documentsDirectory.path,
        'getsomepuzzle',
        _playlistFileName(slug),
      );
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content
            .split('\n')
            .where((l) => l.trim() != puzzleLine.trim())
            .toList();
        await file.writeAsString(lines.join('\n'), mode: FileMode.writeOnly);
      }
    }
  }

  /// Import puzzle lines from a file's content into a playlist.
  Future<void> importToPlaylist(
    String collectionKey,
    String fileContent,
  ) async {
    final lines = fileContent
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();
    for (final line in lines) {
      await addToPlaylist(collectionKey, line.trim());
    }
  }
}
