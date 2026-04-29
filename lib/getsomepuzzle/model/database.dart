import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter/services.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart'
    as equilibrium;
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unicons/unicons.dart';

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
    return "$finishedForLog ${duration}s ${failures}f $lineRepresentation - $sld - $extraFields";
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

class Database {
  List<PuzzleData> puzzles = [];
  String collection = "tutorial";
  Filters currentFilters = Filters();
  bool shouldShuffle = false;
  List<PuzzleData> playlist = [];
  int playerLevel;
  final log = Logger("Database");
  static const _builtInCollectionKeys = {
    'tutorial',
    'default',
    'collection2',
    'custom',
  };

  Database({required this.playerLevel});

  void setPlayerLevel(int newLevel) {
    playerLevel = newLevel;
  }

  List<String> userPlaylistNames = [];

  List<(String, Widget)> getCollections(String customLabel) => [
    for (final (key, label, icon) in [
      ('tutorial', 'Tutorial', UniconsLine.baby_carriage),
      ('default', 'Collection 1', UniconsLine.puzzle_piece),
      ('collection2', 'Collection 2', UniconsLine.puzzle_piece),
      ('custom', customLabel, Icons.build),
    ])
      (
        key,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text(label), Icon(icon)],
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

  void loadStats(List<String> rawStats) {
    log.finest("loadStats");
    final Map<String, StatEntry> solvedPuzzles = {};
    for (final line in rawStats) {
      final entry = StatEntry.parse(line);
      if (entry == null) continue;
      solvedPuzzles[entry.puzzleLine] = entry;
    }
    log.finest("solved $solvedPuzzles");
    for (final puz in puzzles) {
      final entry = solvedPuzzles[puz.lineRepresentation];
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
    String collectionToLoad = (fileToLoad == null)
        ? (prefs.getString("collectionToLoad") ?? "tutorial")
        : fileToLoad;
    final validKeys = {
      ..._builtInCollectionKeys,
      ...userPlaylistNames.map((name) => 'user_${slugify(name)}'),
    };
    if (!validKeys.contains(collectionToLoad)) {
      collectionToLoad = "tutorial";
    }
    collection = collectionToLoad;
    prefs.setString("collectionToLoad", collection);
    await loadUserPlaylists();
    String assetContent;
    if (collection == 'custom' || collection.startsWith('user_')) {
      final slug = collection == 'custom' ? 'custom' : collection.substring(5);
      assetContent = await _loadPlaylist(slug);
    } else {
      try {
        assetContent = await rootBundle.loadString('assets/$collection.txt');
      } catch (_) {
        assetContent = await rootBundle.loadString('assets/tutorial.txt');
      }
    }
    load(assetContent.split("\n"));
    await currentFilters.load();
    final List<String> stats = [];
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      print(prefs.getKeys());
      for (final key in prefs.getKeys()) {
        if (key.startsWith("stats")) {
          log.fine("Loading stats from $key");
          stats.addAll(prefs.getStringList(key) ?? []);
        }
      }
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = p.join(documentsDirectory.path, "getsomepuzzle");
      final pattern = p.join(path, "stats");
      await Directory(path).create(recursive: true);
      for (final file in Directory(path).listSync()) {
        if (file.path.contains(pattern)) {
          log.fine("Loading stats from ${file.path}");
          final fileIo = File(file.path);
          final content = await fileIo.readAsString();
          stats.addAll(content.split("\n"));
        }
      }
    }
    loadStats(stats);
    preparePlaylist();
  }

  Future<void> writeStats() async {
    final List<String> stats = getStats();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList("stats", stats);
      return;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDirectory.path, "getsomepuzzle");
    await Directory(path).create(recursive: true);
    final filePath = p.join(path, "stats.txt");
    final file = File(filePath);

    file.writeAsStringSync(
      stats.sorted().join("\n"),
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

  void preparePlaylist() {
    if (collection == 'tutorial') {
      // Tutorial has a fixed pedagogical order: no shuffle, no level
      // filtering, no user filters — just skip puzzles already completed.
      playlist = puzzles.where((p) => !p.played).toList();
    } else if (shouldShuffle) {
      playlist = filter().toList();
      playlist.shuffle();
    } else {
      playlist = getPuzzlesByLevel(playerLevel);
    }
    log.info(
      "Playlist prepared with ${playlist.length} puzzles (shuffled: $shouldShuffle)",
    );
  }

  /// Erase every stat entry belonging to a tutorial puzzle and reset the
  /// in-memory flags on any tutorial puzzle currently loaded. After this the
  /// player can replay the tutorial from scratch.
  Future<void> restartTutorial() async {
    final tutorialAsset = await rootBundle.loadString('assets/tutorial.txt');
    final tutorialLines = tutorialAsset
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toSet();

    // Reset in-memory flags on any currently-loaded tutorial puzzle.
    for (final puz in puzzles) {
      if (!tutorialLines.contains(puz.lineRepresentation)) continue;
      puz.played = false;
      puz.finished = null;
      puz.skipped = null;
      puz.liked = null;
      puz.disliked = null;
      puz.pleasure = null;
      puz.duration = 0;
      puz.failures = 0;
      puz.hints = 0;
    }

    // Remove tutorial entries from the persisted stats. Unlike `writeStats`
    // (which only sees the currently loaded collection), we rewrite the stats
    // file in-place, keeping every entry that doesn't belong to the tutorial.
    bool keepLine(String line) {
      final entry = StatEntry.parse(line);
      return entry == null || !tutorialLines.contains(entry.puzzleLine);
    }

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (!key.startsWith('stats')) continue;
        final existing = prefs.getStringList(key) ?? [];
        await prefs.setStringList(key, existing.where(keepLine).toList());
      }
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final statsPath = p.join(
        documentsDirectory.path,
        'getsomepuzzle',
        'stats.txt',
      );
      final file = File(statsPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final kept = content.split('\n').where(keepLine).toList();
        await file.writeAsString(kept.join('\n'), mode: FileMode.writeOnly);
      }
    }

    if (collection == 'tutorial') {
      preparePlaylist();
    }
  }

  /// Wipe **every** persisted stat (tutorial + every collection + the
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
      log.info("Playlist empty");
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
      log.info(
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
    log.info("computePlayerLevel: ${toAnalyze.length} puzzles, level=$level");
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

  /// Whether any unplayed puzzle exists in the catalog when user-configured
  /// filters (size, rules) are ignored. Only the baseline exclusions
  /// (played / skipped / disliked) still apply. Used by `EndOfPlaylist`
  /// to distinguish "filters are hiding puzzles" from "really exhausted".
  bool hasUnplayedIgnoringFilters() {
    return puzzles.any(
      (p) => !p.played && p.skipped == null && p.disliked == null,
    );
  }

  List<String> getStats() {
    return puzzles
        .where((puz) => puz.played)
        .map((puz) => puz.getStat())
        .toList();
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
