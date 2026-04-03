import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:flutter/services.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/stats.dart';
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
  }
}

class Filters {
  int minWidth;
  int maxWidth;
  int minHeight;
  int maxHeight;
  int minFilled;
  int maxFilled;
  int minCplx;
  int maxCplx;
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
    this.minCplx = 0,
    this.maxCplx = 100,
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
      minCplx = prefs.getInt("minCplxFilter") ?? 0;
      maxCplx = prefs.getInt("maxCplxFilter") ?? 100;
      wantedRules = (prefs.getStringList("wantedRulesFilter") ?? []).toSet();
      bannedRules = (prefs.getStringList("bannedRulesFilter") ?? []).toSet();
      wantedFlags = (prefs.getStringList("wantedFlagsFilter") ?? []).toSet();
      bannedFlags =
          (prefs.getStringList("bannedFlagsFilter") ??
                  ["played", "skipped", "disliked"])
              .toSet();
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
    prefs.setInt("minCplxFilter", minCplx);
    prefs.setInt("maxCplxFilter", maxCplx);
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
  int maxCplx = 0;
  List<PuzzleData> playlist = [];
  final log = Logger("Database");
  static const _builtInCollections = [
    ("tutorial", "Tutorial", UniconsLine.baby_carriage),
    ("default", "Collection 1", UniconsLine.puzzle_piece),
    ("custom", "Mes puzzles", Icons.build),
  ];

  List<String> userPlaylistNames = [];

  List<(String, Widget)> get collections => [
    for (final (key, label, icon) in _builtInCollections)
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
  List<(String, String)> get writablePlaylistOptions => [
    ('custom', 'Mes puzzles'),
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
      final filePath = p.join(documentsDirectory.path, 'getsomepuzzle', 'playlist_$slug.txt');
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    }
  }
  void load(List<String> lines) {
    puzzles = lines
        .where((e) => e.isNotEmpty && !e.startsWith("#"))
        .map((e) => PuzzleData(e))
        .toList();
    maxCplx = puzzles.isEmpty ? 0 : puzzles.map((puz) => puz.cplx).max;
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
      if (puz.cplx > currentFilters.maxCplx) return false;
      if (puz.cplx < currentFilters.minCplx) return false;
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
    if (collections
        .where((element) => element.$1 == collectionToLoad)
        .isEmpty) {
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
    playlist = filter().toList();
    if (shouldShuffle) {
      playlist.shuffle();
    }
    log.info(
      "Playlist prepared with ${playlist.length} puzzles (shuffled: $shouldShuffle)",
    );
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
    final filePath = p.join(documentsDirectory.path, 'getsomepuzzle', _playlistFileName(slug));
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
    final slug = collectionKey == 'custom' ? 'custom' : collectionKey.replaceFirst('user_', '');
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

  Future<void> deleteFromPlaylist(String collectionKey, String puzzleLine) async {
    final slug = collectionKey == 'custom' ? 'custom' : collectionKey.replaceFirst('user_', '');
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final lines = prefs.getStringList(_playlistPrefsKey(slug)) ?? [];
      lines.remove(puzzleLine);
      await prefs.setStringList(_playlistPrefsKey(slug), lines);
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final filePath = p.join(documentsDirectory.path, 'getsomepuzzle', _playlistFileName(slug));
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n').where((l) => l.trim() != puzzleLine.trim()).toList();
        await file.writeAsString(lines.join('\n'), mode: FileMode.writeOnly);
      }
    }
  }

  /// Import puzzle lines from a file's content into a playlist.
  Future<void> importToPlaylist(String collectionKey, String fileContent) async {
    final lines = fileContent.split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('#')).toList();
    for (final line in lines) {
      await addToPlaylist(collectionKey, line.trim());
    }
  }
}
