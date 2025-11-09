import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:flutter/services.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PuzzleData {
  String lineRepresentation = "";
  List<int> domain = [];
  int width = 0;
  int height = 0;
  int filled = 0;
  List<String> rules = [];
  bool played = false;
  int duration = 0;
  int failures = 0;
  Stats? stats;
  DateTime? started;
  DateTime? finished;
  DateTime? skipped;
  DateTime? liked;
  DateTime? disliked;

  PuzzleData(this.lineRepresentation) {
    lineRepresentation = lineRepresentation.trim();
    var attributesStr = lineRepresentation.split("_");
    final dimensions = attributesStr[1].split("x");
    domain = attributesStr[0].split("").map((e) => int.parse(e)).toList();
    width = int.parse(dimensions[0]);
    height = int.parse(dimensions[1]);
    final cells = attributesStr[2].split("").map((e) => int.parse(e)).toList();
    filled = (cells.where((c) => c > 0).length.toDouble() / cells.length.toDouble() * 100).toInt();
    final strConstraints = attributesStr[3].split(";");
    for (var strConstraint in strConstraints) {
      rules.add(strConstraint.split(":")[0]);
    }
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
    final String finishedForLog = finished == null ? "unfinished" : formatter.format(finished!);
    final dates = [
      skipped != null ? formatter.format(skipped!) : "",
      liked != null ? formatter.format(liked!) : "",
      disliked != null ? formatter.format(disliked!) : "",
    ].join(" - ");
    return "$finishedForLog ${duration}s ${failures}f $lineRepresentation - $sld - $dates";
  }

  Puzzle begin() {
    stats = Stats();
    stats!.begin();
    started = DateTime.now();
    return getPuzzle();
  }

  void stop() {
    if (stats == null) throw UnimplementedError("Should never stop the time before having started it.");
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
      minWidth = prefs.getInt("minWidthFilter") ?? 3;
      maxWidth = prefs.getInt("maxWidthFilter") ?? 6;
      minHeight = prefs.getInt("minHeightFilter") ?? 3;
      maxHeight = prefs.getInt("maxHeightFilter") ?? 8;
      minFilled = prefs.getInt("minPrefilledFilter") ?? 0;
      maxFilled = prefs.getInt("maxPrefilledFilter") ?? 100;
      wantedRules = (prefs.getStringList("wantedRulesFilter") ?? []).toSet();
      bannedRules = (prefs.getStringList("bannedRulesFilter") ?? []).toSet();
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
  }

}

class Database {
  List<PuzzleData> puzzles = [];
  String collection = "tutorial";
  Filters currentFilters = Filters();
  bool shouldShuffle = false;
  List<PuzzleData> playlist = [];
  final log = Logger("Database");

  void load(List<String> lines) {
    puzzles = lines
      .where((e) => e.isNotEmpty && !e.startsWith("#"))
      .map((e) => PuzzleData(e))
      .toList();
  }

  void loadStats(List<String> stats) {
    log.finest("loadStats");
    final Map<String, List<String>> solvedPuzzles = {};
    for (final stat in stats) {
      log.finest("stat $stat");
      final List<String> statFields = stat.split(" ");
      log.finest("statFields $statFields");
      if (statFields.length < 4) continue;
      solvedPuzzles[statFields[3]] = statFields;
    }
    log.finest("solved $solvedPuzzles");
    for (final puz in puzzles) {
      if (!solvedPuzzles.containsKey(puz.lineRepresentation)) continue;
      puz.played = true;
      final puzzleData = solvedPuzzles[puz.lineRepresentation];
      if (puzzleData![0] != "unfinished") {
        puz.finished = DateTime.tryParse(puzzleData[0]);
      }
      if (puzzleData.length > 7 && puzzleData[7].isNotEmpty) {
        puz.skipped = DateTime.tryParse(puzzleData[7]);
      }
      if (puzzleData.length > 9 && puzzleData[9].isNotEmpty) {
        puz.liked = DateTime.tryParse(puzzleData[9]);
      }
      if (puzzleData.length > 11 && puzzleData[11].isNotEmpty) {
        puz.disliked = DateTime.tryParse(puzzleData[11]);
      }
      puz.duration = int.parse(
        puzzleData[1].replaceAll("s", ""),
      );
      puz.failures = int.parse(
        puzzleData[2].replaceAll("f", ""),
      );
    }
  }

  Iterable<PuzzleData> filter() {
    return puzzles.where((puz) {
      if (puz.played && currentFilters.bannedFlags.contains("played")) return false;
      if (puz.skipped != null && currentFilters.bannedFlags.contains("skipped")) return false;
      if (puz.liked != null && currentFilters.bannedFlags.contains("liked")) return false;
      if (puz.disliked != null && currentFilters.bannedFlags.contains("disliked")) return false;

      if (!puz.played && currentFilters.wantedFlags.contains("played")) return false;
      if (puz.skipped == null && currentFilters.wantedFlags.contains("skipped")) return false;
      if (puz.liked == null && currentFilters.wantedFlags.contains("liked")) return false;
      if (puz.disliked == null && currentFilters.wantedFlags.contains("disliked")) return false;

      if (puz.filled > currentFilters.maxFilled) return false;
      if (puz.filled < currentFilters.minFilled) return false;
      if (puz.width > currentFilters.maxWidth) return false;
      if (puz.width < currentFilters.minWidth) return false;
      if (puz.height > currentFilters.maxHeight) return false;
      if (puz.height < currentFilters.minHeight) return false;
      if (currentFilters.wantedRules.isNotEmpty &&
          currentFilters.wantedRules.intersection(puz.rules.toSet()).length != currentFilters.wantedRules.length) {
        return false;
      }
      if (currentFilters.bannedRules.isNotEmpty &&
          currentFilters.bannedRules.intersection(puz.rules.toSet()).isNotEmpty) {
        return false;
      }
      return true;
    });
  }

  Future<void> loadPuzzlesFile([String? fileToLoad]) async {
    if (fileToLoad != null) {
      collection = fileToLoad;
    }
    final assetContent = await rootBundle.loadString('assets/$collection.txt');
    load(assetContent.split("\n"));
    await currentFilters.load();
    final List<String> stats = [];
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      stats.addAll(prefs.getStringList('stats') ?? []);
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = p.join(documentsDirectory.path, "getsomepuzzle");
      await Directory(path).create(recursive: true);
      String filePath = p.join(path, "stats_$collection.txt");
      if (collection == "puzzles") filePath = p.join(path, "stats.txt");
      log.fine("Loading stats from $filePath");
      final file = File(filePath);
      if (!(await file.exists())) {
        log.warning("Stats file does not exist");
        file.createSync();
      }
      final content = await file.readAsString();
      print(content);
      stats.addAll(content.split("\n"));
    }
    log.finest("Stats to load $stats");
    loadStats(stats);
    preparePlaylist();
  }

  Future<void> writeStats() async {
    final List<String> stats = getStats();
    String statsName = "stats_$collection";
    if (collection == "puzzles") statsName = "stats";
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(statsName, stats);
      return;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDirectory.path, "getsomepuzzle");
    await Directory(path).create(recursive: true);
    final filePath = p.join(path, "$statsName.txt");
    log.fine("Writing stats to $filePath");
    final file = File(filePath);

    file.writeAsStringSync(
      stats.join("\n"),
      mode: FileMode.writeOnly,
      flush: true,
    );
  }

  void preparePlaylist() {
    playlist = filter().toList();
    log.info("Playlist prepared with ${playlist.length} puzzles");
  }

  void removePuzzleFromPlaylist(PuzzleData puz) {
    playlist.remove(puz);
  }

  PuzzleData? next() {
    if (playlist.isEmpty) {
      log.info("Playlist empty");
      preparePlaylist();
    }
    if (playlist.isEmpty) return null;
    if (shouldShuffle) {
      playlist.shuffle();
    }
    final selection = playlist.removeAt(0);
    log.finer("${playlist.length} puzzles remaining in playlist");
    writeStats();
    return selection;
  }

  List<String> getStats() {
    return puzzles.where((puz) => puz.played).map((puz) => puz.getStat()).toList();
  }

}
