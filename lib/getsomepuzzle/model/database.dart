import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter/services.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart'
    as equilibrium;
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';
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
  userAllPlayed,
  noPuzzlesLoaded,
  filtersTooStrict,
  onboardingPhase,
  softFilter,
  generic,
}

class PuzzleData {
  String lineRepresentation = "";
  List<int> domain = [];
  int width = 0;
  int height = 0;
  int filled = 0;
  int cplx = 0;
  List<String> rules = [];
  bool played = false;
  int duration = 0;
  int failures = 0;
  int hints = 0;
  // Cell-modification analytics persisted across plays. Default 0 for older
  // stats lines that pre-date the instrumentation. See Stats.recordCellEdit.
  int cellEdits = 0;
  int firstClickMs = 0;
  int longestGapMs = 0;
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
      rules.add(strConstraint.split(":")[0]);
    }
    cplx = int.tryParse(attributesStr[6]) ?? 0;
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
  final log = Logger("Filters");

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
    this.bannedFlags = const {"played", "skipped", "disliked"},
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
                  ["played", "skipped", "disliked"])
              .toSet();
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
  }
}

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
  String collection = entryCollectionKey;
  Filters currentFilters = Filters();
  bool shouldShuffle = false;
  List<PuzzleData> playlist = [];
  int playerLevel;
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

  /// Slug of the entry-level collection — the default landing collection
  /// for new players, and the fallback target for legacy stored values
  /// like "tutorial" / "default" / "collection2" / "collection3" that no
  /// longer exist post-merge.
  static const entryCollectionKey = '1-easy';

  /// Per-constraint mastery tracker. Populated by [loadStats] from the
  /// player's history (so reinstalls or device transfers reconstruct
  /// the map from stats alone) and consulted by the onboarding modal.
  /// Optional: when null, no first-seen recording happens — callers
  /// that don't need the onboarding flow (CLI tools, tests) can skip
  /// wiring it.
  final ConstraintProgress? progress;

  Database({required this.playerLevel, this.progress});

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
    puzzles = lines
        .where((e) => e.isNotEmpty && !e.startsWith("#"))
        .map((e) => PuzzleData(e))
        .toList();
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

  /// Count of finished, non-skipped plays attributed to the
  /// onboarding journey. Bumped via [notePuzzleCompleted] and
  /// persisted to `SharedPreferences`. Drives [currentPhase] — every
  /// 10th completion advances the player to the next onboarding phase
  /// until they graduate past the last defined phase. Reset to 0 by
  /// the "Replay onboarding" button.
  Map<String, int> onboardingCompletions = {};

  static const _onboardingCompletionsKey = 'onboardingCompletions';

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
    _globalUsablePlays++;
    for (final slug in puz.rules.toSet()) {
      if (slug.isEmpty || slug == 'TX') continue;
      _playCountBySlug.update(slug, (v) => v + 1, ifAbsent: () => 1);
    }
    final wasOnboarding = currentPhase != null;
    if (wasOnboarding) {
      for (var slug in puz.rules) {
        onboardingCompletions[slug] = onboardingCompletions[slug] == null
            ? 1
            : onboardingCompletions[slug]! + 1;
      }
      // Fire-and-forget: persistence failures only mean the counter
      // resets on next launch, which the player will perceive as a
      // benign delay (one extra puzzle in the same phase).
      _persistOnboardingCompletions();
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

  /// Reset the onboarding counter so the player re-enters phase 0.
  /// Pairs with `ConstraintProgress.clear()` for the full
  /// "Rejouer l'onboarding" workflow. Persists immediately because
  /// `loadPuzzlesFile` (typically called right after) re-reads the
  /// counter from prefs and would otherwise silently undo the reset.
  Future<void> resetOnboardingProgress() async {
    onboardingCompletions = {};
    await _persistOnboardingCompletions();
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
    await _persistOnboardingCompletions();
  }

  /// Mix in puzzles from `assets/overfilled-easy.txt` into the catalog
  /// while the player is in onboarding on the entry-level collection.
  ///
  /// Why: phases 4 (DF) and 5 (CC) — and likely later phases — are
  /// extremely thin in `1-easy` because the generator naturally
  /// produces simple-rule, small-grid puzzles with high prefill (they
  /// classify as `overfilled` even when their solving trace is
  /// beginner-level). `overfilled-easy.txt` holds exactly those
  /// puzzles: `overfilled` by prefill ratio, `beginner` by trace
  /// shape — pedagogically appropriate for onboarding (high prefill
  /// = the rule does most of the work).
  ///
  /// The split is decided at generation time by `classifyTrace`
  /// (cf. `lib/getsomepuzzle/level.dart`), so the runtime doesn't
  /// have to second-guess
  /// classification on every load — anything in `overfilled-easy.txt`
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
      content = await rootBundle.loadString('assets/overfilled-easy.txt');
    } catch (e) {
      log.fine(
        'overfilled-easy.txt missing, skipping onboarding augmentation: $e',
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
      'Augmented onboarding catalog with $added overfilled-easy puzzles',
    );
  }

  void loadStats(List<String> rawStats) {
    log.finest("loadStats");
    // Index by canonical key (identity-only): old stats lines that embed
    // a stale complexity score or constraint order still match the current
    // puzzle line. See lib/getsomepuzzle/model/canonical.dart.
    final Map<String, StatEntry> solvedPuzzles = {};
    int usablePlays = 0;
    _playCountBySlug.clear();
    for (final line in rawStats) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      solvedPuzzles[canonicalPuzzleKey(entry.puzzleLine)] = entry;
      if (entry.finished != null && entry.skipped == null) {
        usablePlays++;
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
    log.finest("solved $solvedPuzzles");
    for (final puz in puzzles) {
      final entry = solvedPuzzles[canonicalPuzzleKey(puz.lineRepresentation)];
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
    }
  }

  Iterable<PuzzleData> filter() {
    return puzzles.where((puz) {
      if (puz.played && currentFilters.bannedFlags.contains("played")) {
        return false;
      }
      if (puz.skipped != null &&
          currentFilters.bannedFlags.contains("skipped")) {
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
      if (puz.skipped == null &&
          currentFilters.wantedFlags.contains("skipped")) {
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
      if (puz.width > currentFilters.maxWidth) return false;
      if (puz.width < currentFilters.minWidth) return false;
      if (puz.height > currentFilters.maxHeight) return false;
      if (puz.height < currentFilters.minHeight) return false;
      if (currentFilters.wantedRules.isNotEmpty &&
          currentFilters.wantedRules.intersection(puz.rules.toSet()).length !=
              currentFilters.wantedRules.length) {
        return false;
      }
      if (currentFilters.bannedRules.isNotEmpty &&
          currentFilters.bannedRules
              .intersection(puz.rules.toSet())
              .isNotEmpty) {
        return false;
      }
      return true;
    });
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
    await currentFilters.load();
    final stats = await _readRawStatsFromStorage();
    loadStats(stats);
    preparePlaylist();
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
      final path = p.join(documentsDirectory.path, "getsomepuzzle");
      final pattern = p.join(path, "stats");
      await Directory(path).create(recursive: true);
      for (final entry in Directory(path).listSync()) {
        if (entry is! File || !entry.path.contains(pattern)) continue;
        log.finer("Loading stats from ${entry.path}");
        final content = await entry.readAsString();
        stats.addAll(content.split("\n"));
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
  /// stats files + any imported file), dedupe by canonical puzzle key, and
  /// overlay the current session's plays on top so they win on conflict.
  /// The result is written back to the canonical `stats.txt` (or the
  /// `"stats"` `SharedPreferences` key on web). Legacy / imported stat
  /// files are left untouched — the canonical-key dedupe at load time
  /// keeps everything coherent, and the redundancy survives a `clearAllStats`
  /// because that helper deletes every `stats*` file outright.
  Future<void> writeStats() async {
    final raw = await _readRawStatsFromStorage();
    final Map<String, String> byKey = {};
    for (final line in raw) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      byKey[canonicalPuzzleKey(entry.puzzleLine)] = line;
    }
    final fromSession = getStats();
    for (final line in fromSession) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      byKey[canonicalPuzzleKey(entry.puzzleLine)] = line;
    }
    final merged = byKey.values.toList()..sort();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList("stats", merged);
      return;
    }
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
  /// Custom, and user playlists are not capped.
  static const int playlistBatchSize = 5;

  bool _isPlayableLevel(String key) =>
      playableCollectionKeyToLevel.containsKey(key);

  void preparePlaylist() {
    if (collection == 'custom' || collection.startsWith('user_')) {
      // User-curated playlists keep their insertion order — the player
      // chose this sequence explicitly. Filters and shuffle do not
      // apply; only "already played" is honoured. The onboarding
      // phase filter is *not* applied here either: importing or
      // hand-crafting a playlist is an opt-in that supersedes the
      // curated track.
      playlist = puzzles.where((p) => !p.played).toList();
    } else {
      final phase = currentPhase;
      if (phase != null && _isPlayableLevel(collection)) {
        if (shouldShuffle) {
          // Shuffle within phase-eligible puzzles so the player who
          // explicitly opted into shuffle still doesn't get
          // multi-constraint surprises during strict onboarding.
          playlist =
              filter()
                  .where((p) => puzzleEligibleForPhase(p.rules, phase))
                  .toList()
                ..shuffle();
        } else {
          playlist = _getPuzzlesInPhase(phase);
        }
      } else {
        if (shouldShuffle) {
          playlist = filter().toList()..shuffle();
        } else {
          playlist = getPuzzlesByLevel(playerLevel);
        }
        // Soft filter applies whether the player went via shuffle or
        // the regular sampler — the goal is "≤1 unseen slug per
        // proposed puzzle" regardless of selection mechanism.
        playlist = _applySoftOnboardingFilter(playlist);
      }
      _maybeCapBatch();
    }
    log.fine(
      "Playlist prepared with ${playlist.length} puzzles "
      "(shuffled: $shouldShuffle, capped: ${_isPlayableLevel(collection)}, "
      "phase: ${currentPhase?.index}, "
      "softFilter: ${_softFilterActive ? 'on' : 'off'})",
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
      return EmptyPlaylistReason.userAllPlayed;
    }
    if (puzzles.isEmpty) {
      return EmptyPlaylistReason.noPuzzlesLoaded;
    }
    if (filter().isEmpty) {
      return EmptyPlaylistReason.filtersTooStrict;
    }
    if (currentPhase != null && _isPlayableLevel(collection)) {
      return EmptyPlaylistReason.onboardingPhase;
    }
    if (_softFilterActive) {
      return EmptyPlaylistReason.softFilter;
    }
    return EmptyPlaylistReason.generic;
  }

  /// Drop puzzles that would force the player to meet two or more new
  /// constraints in a single grid. Pure pass-through when the soft
  /// filter is inactive (no [progress] wired, still in a strict phase,
  /// or every slug already met).
  List<PuzzleData> _applySoftOnboardingFilter(List<PuzzleData> input) {
    if (!_softFilterActive) return input;
    final p = progress!;
    return input
        .where((puz) => puzzlePassesSoftFilter(puz.rules, p.isFirstTimeFor))
        .toList();
  }

  /// Phase-aware variant of [getPuzzlesByLevel]: same Gaussian-on-cplx
  /// + variety bias, plus a multiplicative phase weight that filters
  /// out-of-phase puzzles (weight 0) and gives a 4× boost to puzzles
  /// containing the slug being introduced (≈ 80/20 expected ratio
  /// between introduction and refresh puzzles).
  ///
  /// The Gaussian still centers on the player's `playerLevel`: the
  /// catalog itself is bounded to `1-easy + overfilled-easy`, both of
  /// which are *beginner* by trace shape, so a fast learner's higher
  /// level just biases sampling toward the upper end of *that*
  /// bucket — never out of it.
  ///
  /// Falls back to the regular [getPuzzlesByLevel] result when the
  /// phase filter would leave the playlist empty — this avoids
  /// stranding a player on an out-of-track collection during
  /// onboarding (e.g., they wandered from `1-easy` into `6-mad` mid
  /// onboarding; nothing in 6-mad will satisfy a phase 1 filter, so
  /// we just give them the regular pick).
  List<PuzzleData> _getPuzzlesInPhase(OnboardingPhase phase) {
    final mu = playerLevel + selectionOffset;
    final twoSigmaSq = 2 * selectionSigma * selectionSigma;
    final filtered = filter().toList();
    final eligible = filtered
        .where((p) => puzzleEligibleForPhase(p.rules, phase))
        .toList();
    if (eligible.isEmpty) {
      // Out-of-track collection (e.g., player jumped from 1-easy to
      // 6-mad mid-onboarding). Fall through to the regular sampler so
      // they still get something playable, even if the phase filter
      // produced nothing.
      return getPuzzlesByLevel(playerLevel);
    }
    final varietyStats = _buildRecencyWeightedStats(eligible);
    final keyed = eligible.map((p) {
      final d = p.cplx - mu;
      final wCplx = math.exp(-math.min(d * d / twoSigmaSq, 700));
      final gap = _varietyGapForPuzzle(p, varietyStats);
      final wVariety = 1 + selectionVarietyAlpha * gap;
      final wPhase =
          (puzzleEligibleForPhase(p.rules, phase) &&
              p.rules.contains(phase.introducing)
          ? 1
          : 0);
      final w = wCplx * wVariety * wPhase;
      final u = _samplingRandom.nextDouble() + 1e-300;
      final key = -math.log(u) / w;
      return (p, key);
    }).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    return keyed.map((e) => e.$1).toList();
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
  ///     needed).
  String? get recommendedCollectionKey {
    if (currentPhase != null) return null;
    if (_globalUsablePlays < _minPlaysForRecommendation) return null;
    final level = recommendedLevelFor(playerLevel);
    final key = levelToPlayableCollectionKey[level];
    return (key == null || key == collection) ? null : key;
  }

  /// Wipe **every** persisted stat (every collection + the
  /// recency window that drives [computePlayerLevel] and the variety
  /// bias) and reset the in-memory flags on every loaded puzzle.
  /// Destructive — there is no undo. The stored player level in
  /// [Settings] is intentionally left alone (it's outside the scope of
  /// "stats").
  Future<void> clearAllStats() async {
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
      final dirPath = p.join(documentsDirectory.path, 'getsomepuzzle');
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        // Remove every `stats*` file, not just `stats.txt`. Older
        // collections leave behind `stats_<collection>.txt` files that
        // are still loaded by `loadPuzzlesFile` — leaving them in place
        // would silently restore play history on the next launch.
        for (final entry in dir.listSync()) {
          if (entry is File && p.basename(entry.path).startsWith('stats')) {
            await entry.delete();
          }
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
    writeStats();
    return selection;
  }

  /// Expected duration (seconds) for a puzzle of given `cplx`, `cells`,
  /// `failures`, and `nConstraints` (the puzzle's constraint count).
  ///
  /// Refit by OLS on real plays after stricter outlier rejection (see
  /// notes below). Anchored model:
  ///   log(dur) ≈ 1.197 + 0.00808·cplx + 0.515·log(cells)
  ///                    + 0.151·failures + 0.102·n_constraints
  ///   ≈ 3.31 · cells^0.515 · exp(cplx/123.8)
  ///        · 1.163^failures · 1.107^n_constraints       (R²=0.50, MAPE=50 %)
  ///
  /// The intercept is anchored so that — on the calibration corpus — the
  /// **mean** `level_i` lands on 50 rather than on the corpus's mean
  /// `cplx`. Concretely: a player who solves at the same pace as the
  /// calibration corpus converges to level 50; faster players go above,
  /// slower below. This places the "average" right in the middle of
  /// [0, 100] instead of bunching at the low end.
  ///
  /// **Why these constants and not the previous ones (8.62, 27.3, …)**:
  /// the earlier fit used an AFK-tolerant outlier rule (cap at 1800 s but
  /// no idle-gap filter), which let plays with multi-minute idle gaps
  /// inflate the `exp(cplx/27.3)` slope to absurd levels (predicted
  /// duration ~30 min for cplx=80, ~1.6 h for cplx=100 8×8). Refiltering
  /// on `longestGapMs ≤ 30 s` flattens the cplx slope to its true
  /// behaviour on the data. The new R²/MAPE are slightly worse than the
  /// stale model's because we deliberately stop fitting the AFK tail —
  /// what we lose in residual variance we gain in not pretending high-cplx
  /// puzzles take half an hour.
  ///
  /// See `bin/analyze_stats.dart` for the regression tool (it both
  /// applies the same cleaning and prints anchored constants ready to
  /// paste back here).
  static const _kBase = 3.3108;
  static const _kCellsExp = 0.5146;
  static const _kCplxScale = 123.82;
  static const _kFailMul = 1.1627;
  static const _kNConsMul = 1.1069;

  static double _expectedDuration(
    int cplx,
    int cells,
    int failures,
    int nConstraints,
  ) {
    return _kBase *
        math.pow(cells, _kCellsExp) *
        math.exp(cplx / _kCplxScale) *
        math.pow(_kFailMul, failures) *
        math.pow(_kNConsMul, nConstraints);
  }

  /// Algebraic inverse of `_expectedDuration`: given an observed play, the
  /// `cplx` value the model would have predicted for that duration. Used
  /// by the skill inversion in `computePlayerLevel`.
  static double _impliedCplx(
    int dur,
    int cells,
    int failures,
    int nConstraints,
  ) {
    return _kCplxScale *
        (math.log(dur) -
            math.log(_kBase) -
            _kCellsExp * math.log(cells) -
            failures * math.log(_kFailMul) -
            nConstraints * math.log(_kNConsMul));
  }

  /// Compute the player's implicit level (in `cplx` units) from recent plays.
  ///
  /// Returns `fallback` when there are fewer than 10 usable samples — this
  /// preserves a manually set level rather than snapping back to 0.
  int computePlayerLevel({required int fallback}) {
    final playedPuzzles = puzzles
        .where(
          (p) =>
              p.played &&
              p.finished != null &&
              p.skipped == null &&
              p.duration > 0,
        )
        .toList();
    if (playedPuzzles.length < 2) {
      log.fine(
        "computePlayerLevel: only ${playedPuzzles.length} usable samples, keeping stored level $fallback",
      );
      return fallback;
    }
    playedPuzzles.sort((a, b) => b.finished!.compareTo(a.finished!));
    final toAnalyze = playedPuzzles.take(50).toList();

    double weightedSum = 0;
    double weightTotal = 0;
    for (var i = 0; i < toAnalyze.length; i++) {
      final puz = toAnalyze[i];
      final cells = puz.width * puz.height;
      if (cells <= 0) continue;
      final nCons = puz.rules.length;
      final expected = _expectedDuration(puz.cplx, cells, puz.failures, nCons);
      // Clamp duration to neutralise puzzles left open for hours and to keep
      // log() finite if the timer recorded zero somehow.
      final clampedDur = puz.duration.clamp(1, (expected * 10).round());
      // Skill inversion: when the play's duration matches the expected
      // value for its `cplx`, `level_i = cplx`. Faster than expected ⇒
      // higher implicit level; slower ⇒ lower. Derived as
      //   level_i = 2·cplx − implied_cplx_for(this duration)
      // where implied_cplx is the proper inverse of `_expectedDuration`.
      final levelI =
          2 * puz.cplx - _impliedCplx(clampedDur, cells, puz.failures, nCons);
      // Exponential decay, half-life = 25 puzzles.
      final weight = math.pow(0.5, i / 25.0).toDouble();
      weightedSum += levelI * weight;
      weightTotal += weight;
    }
    if (weightTotal <= 0) return fallback;
    final level = (weightedSum / weightTotal).round().clamp(0, 100);
    log.fine("computePlayerLevel: ${toAnalyze.length} puzzles, level=$level");
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
    final filtered = filter().toList();
    final varietyStats = _buildRecencyWeightedStats(filtered);
    final keyed = filtered.map((p) {
      final d = p.cplx - mu;
      // Clamp the exponent to avoid `exp` underflow producing key = +∞ for
      // every puzzle on the tail (which would then sort arbitrarily).
      final wCplx = math.exp(-math.min(d * d / twoSigmaSq, 700));
      final gap = _varietyGapForPuzzle(p, varietyStats);
      final wVariety = 1 + selectionVarietyAlpha * gap;
      final w = wCplx * wVariety;
      // The +1e-300 below guards against `nextDouble() == 0`, which would
      // make `−ln(u)` infinite and corrupt the sort.
      final u = _samplingRandom.nextDouble() + 1e-300;
      final key = -math.log(u) / w;
      return (p, key);
    }).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    return keyed.map((e) => e.$1).toList();
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
      final key = (p.width, p.height);
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
      allowedSizes.add((p.width, p.height));
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
    final distinct = p.rules.toSet();
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
        final c = stats.sizeCounts[(p.width, p.height)] ?? 0;
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
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dirPath = p.join(documentsDirectory.path, 'getsomepuzzle');
      await Directory(dirPath).create(recursive: true);
      final filePath = p.join(dirPath, 'stats_imported_$timestamp.txt');
      File(filePath).writeAsStringSync(
        validLines.join('\n'),
        mode: FileMode.writeOnly,
        flush: true,
      );
    }
    final allStats = await _readRawStatsFromStorage();
    loadStats(allStats);
    preparePlaylist();
    return validLines.length;
  }

  /// Every persisted stat line across **all** collections, deduplicated by
  /// canonical puzzle key (the same key used by [loadStats] so legacy lines
  /// embedding a stale `cplx` still collapse with the current line).
  ///
  /// In-session plays from the currently-loaded collection are folded in
  /// last so they take precedence over any older snapshot still on disk —
  /// otherwise viewing or sharing right after finishing a puzzle would
  /// surface its previous entry (or nothing) instead of the just-recorded
  /// timings.
  Future<List<String>> getAllStats() async {
    final raw = await _readRawStatsFromStorage();
    final Map<String, String> byKey = {};
    for (final line in raw) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      byKey[canonicalPuzzleKey(entry.puzzleLine)] = line;
    }
    for (final puz in puzzles.where((p) => p.played)) {
      byKey[canonicalPuzzleKey(puz.lineRepresentation)] = puz.getStat();
    }
    final result = byKey.values.toList()..sort();
    return result;
  }

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
