import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter/services.dart';
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

class Database {
  List<PuzzleData> puzzles = [];
  String collection = "tutorial";
  Filters currentFilters = Filters();
  bool shouldShuffle = false;
  List<PuzzleData> playlist = [];
  int playerLevel;
  final log = Logger("Database");
  static const _builtInCollectionKeys = {'tutorial', 'default', 'custom'};

  Database({required this.playerLevel});

  void setPlayerLevel(int newLevel) {
    playerLevel = newLevel;
  }

  List<String> userPlaylistNames = [];

  List<(String, Widget)> getCollections(String customLabel) => [
    for (final (key, label, icon) in [
      ('tutorial', 'Tutorial', UniconsLine.baby_carriage),
      ('default', 'Collection 1', UniconsLine.puzzle_piece),
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
    log.fine("Writing stats");
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

  /// Expected duration (seconds) for a puzzle of given `cplx` and `cells`,
  /// adjusted by `failures`.
  ///
  /// Calibrated by log-linear regression on ~1300 real plays:
  ///   log(dur) = -0.086 + 0.01356·cplx + 1.009·log(cells) + 0.504·failures
  /// ≈ 0.92 · cells · exp(cplx/75) · 1.65^failures  (R²=0.45, MAPE=56%).
  ///
  /// `cplx` is clipped to 80: the complexity formula attributes 100 to any
  /// puzzle needing backtracking, including those trivially guessed, which
  /// biases the model at the high end.
  static double _expectedDuration(int cplx, int cells, int failures) {
    final clampedCplx = cplx.clamp(0, 100) / 100;

    return cells *
        1.25 *
        math.exp(clampedCplx) *
        math.exp(clampedCplx) *
        math.pow(1.65, failures);
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
      final expected = _expectedDuration(puz.cplx, cells, puz.failures);
      // Clamp duration to neutralise puzzles left open for hours.
      final clampedDur = puz.duration.clamp(1, (expected * 10).round());
      final ratio = expected / clampedDur.toDouble();
      final levelI = ratio * puz.cplx;
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

  /// Puzzles in a `[level-1, level+2]` window around `level`. Asymmetric on
  /// purpose: nudges the player slightly upward while keeping one easier tier
  /// for variety. Empty list means the player has exhausted their tier —
  /// surfaced to the UI via `EndOfPlaylist`.
  List<PuzzleData> getPuzzlesByLevel(int level) {
    final candidates = filter()
        .where((p) => p.cplx >= level - 1 && p.cplx <= level + 2)
        .toList();
    candidates.shuffle();
    return candidates;
  }

  /// Whether any unplayed puzzle exists at `level` when user-configured
  /// filters (size, rules) are ignored. Only the baseline exclusions
  /// (played / skipped / disliked) still apply. Used by `EndOfPlaylist`
  /// to distinguish "filters are hiding puzzles" from "really exhausted".
  bool hasUnplayedAtLevelIgnoringFilters(int level) {
    return puzzles.any(
      (p) =>
          !p.played &&
          p.skipped == null &&
          p.disliked == null &&
          p.cplx >= level - 1 &&
          p.cplx <= level + 2,
    );
  }

  /// Smallest level strictly greater than `currentLevel` for which
  /// `getPuzzlesByLevel` would return at least one candidate. Returns `null`
  /// if the player has truly reached the top of the filtered catalog.
  int? nextPopulatedLevel(int currentLevel) {
    final filteredCplxs = filter().map((p) => p.cplx).toList();
    for (int l = currentLevel + 1; l <= 100; l++) {
      if (filteredCplxs.any((c) => c >= l - 1 && c <= l + 2)) return l;
    }
    return null;
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
