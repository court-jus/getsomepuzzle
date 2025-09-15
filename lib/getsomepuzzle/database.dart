import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:intl/intl.dart';
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

  Puzzle begin() {
    stats = Stats();
    stats!.begin();
    started = DateTime.now();
    return getPuzzle();
  }

  String stop() {
    if (stats == null) throw UnimplementedError("Should never stop the time before having started it.");
    final stat = stats!.stop(lineRepresentation);
    played = true;
    finished = DateTime.now();
    duration = stats!.duration;
    failures = stats!.failures;
    return stat;
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

  Filters({
    this.minWidth = 3,
    this.maxWidth = 6,
    this.minHeight = 3,
    this.maxHeight = 8,
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
      print("Error $e");
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
  Filters currentFilters = Filters();
  List<PuzzleData> playlist = [];

  void load(List<String> lines) {
    puzzles = lines.where((e) => e.isNotEmpty).map((e) => PuzzleData(e)).toList();
  }

  void loadStats(List<String> stats) {
    final Map<String, List<String>> solvedPuzzles = {};
    for (final stat in stats) {
      final List<String> statFields = stat.split(" ");
      if (statFields.length != 5) continue;
      solvedPuzzles[statFields[4]] = statFields;
    }
    for (final puz in puzzles) {
      if (!solvedPuzzles.containsKey(puz.lineRepresentation)) continue;
      puz.played = true;
      final puzzleData = solvedPuzzles[puz.lineRepresentation];
      // 0: date, 1: duration, 2: " - ", 3: failures, 4: lineRepr
      puz.duration = int.parse(
        puzzleData![1].replaceAll("s", ""),
      );
      puz.failures = int.parse(
        puzzleData[3].replaceAll("f", ""),
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
          currentFilters.wantedRules.intersection(puz.rules.toSet()).isEmpty) {
        return false;
      }
      if (currentFilters.bannedRules.isNotEmpty &&
          currentFilters.bannedRules.intersection(puz.rules.toSet()).isNotEmpty) {
        return false;
      }
      return true;
    });
  }

  Future<void> loadPuzzlesFile() async {
    final assetContent = await rootBundle.loadString('assets/puzzles.txt');
    load(assetContent.split("\n"));
  }

  void preparePlaylist() {
    playlist = filter().whereNot((puz) => puz.played).toList();
  }

  PuzzleData? next() {
    if (playlist.isEmpty) {
      preparePlaylist();
    }
    if (playlist.isEmpty) return null;
    final selection = playlist.removeAt(0);
    playlist.add(selection);
    return selection;
  }

  List<String> getStats() {
    final now = DateTime.now();
    final DateFormat formatter = DateFormat('yyyy-MM-ddTHH:mm:ss');
    final String dateForLog = formatter.format(now);
    return filter().where((puz) => puz.played).map((puz) => "$dateForLog ${puz.duration}s - ${puz.failures}f ${puz.lineRepresentation}").toList();
  }

}
