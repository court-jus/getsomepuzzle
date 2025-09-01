// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/help.dart';
import 'package:getsomepuzzle/widgets/open.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:getsomepuzzle/widgets/stats_btn.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'getsomepuzzle/puzzle.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Get Some Puzzle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Get Some Puzzle'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool helpVisible = false;
  String topMessage = "";
  String bottomMessage = "";
  Puzzle? currentPuzzle;
  List<String> unsolvedPuzzles = [];
  int puzzleCount = 0;
  bool shouldCheck = false;
  List<String> stats = [];
  List<int> history = [];

  @override
  void initState() {
    super.initState();
    loadStats();
    Timer.periodic(Duration(seconds: 1), (tmr) {
      setState(() {
        int played = puzzleCount - unsolvedPuzzles.length;
        String statsText = currentPuzzle == null
            ? ""
            : currentPuzzle!.stats.toString();
        bottomMessage = "$played/$puzzleCount - $statsText";
      });
    });
  }

  Future<void> loadStats() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      stats = prefs.getStringList('stats') ?? [];
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = p.join(documentsDirectory.path, "getsomepuzzle");
      await Directory(path).create(recursive: true);
      final filePath = p.join(path, "stats.txt");
      final file = File(filePath);
      if (!(await file.exists())) {
        file.createSync();
      }
      final content = await file.readAsString();
      setState(() {
        stats = content.split("\n");
      });
    }
    await loadPuzzles();
    loadPuzzle();
  }

  Future<List<String>> loadPuzzles() async {
    if (unsolvedPuzzles.isNotEmpty) return unsolvedPuzzles;
    final assetContent = await rootBundle.loadString('assets/puzzles.txt');
    final allPuzzles = assetContent.split("\n");
    puzzleCount = allPuzzles.length;
    final Set<String> solvedPuzzles = {};
    for (final stat in stats) {
      final List<String> statFields = stat.split(" ");
      if (statFields.length != 5) continue;
      solvedPuzzles.add(statFields[4]);
    }
    for (final puz in allPuzzles) {
      if (solvedPuzzles.contains(puz)) continue;
      unsolvedPuzzles.add(puz);
    }

    unsolvedPuzzles.shuffle();
    return unsolvedPuzzles;
  }

  void loadPuzzle() async {
    try {
      final randomPuzzle = unsolvedPuzzles.removeAt(0);
      print(randomPuzzle);
      setState(() {
        currentPuzzle = Puzzle(randomPuzzle);
        currentPuzzle!.stats.begin();
      });
    } catch (e) {
      currentPuzzle = null;
    }
  }

  void openPuzzle(String puz) {
    setState(() {
      currentPuzzle = Puzzle(puz);
      currentPuzzle!.stats.begin();
    });
  }

  void restartPuzzle() {
    if (currentPuzzle == null) return;
    setState(() {
      topMessage = "";
      history = [];
      currentPuzzle!.restart();
      currentPuzzle!.check();
    });
  }

  void undo() {
    if (currentPuzzle == null || history.isEmpty) return;
    setState(() {
      currentPuzzle!.resetCell(history.removeLast());
      currentPuzzle!.check();
      topMessage = "";
    });
  }

  void handlePuzzleTap(int idx) {
    if (currentPuzzle == null) return;
    setState(() {
      currentPuzzle!.incrValue(idx);
      if (history.isEmpty || history.last != idx) history.add(idx);
      shouldCheck = currentPuzzle!.complete;
      if (shouldCheck) Future.delayed(Duration(seconds: 1), autoCheck);
    });
  }

  Future<void> writeStat(String text) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('stats', stats);
      return;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDirectory.path, "getsomepuzzle");
    await Directory(path).create(recursive: true);
    final filePath = p.join(path, "stats.txt");
    final file = File(filePath);

    file.writeAsStringSync("$text\n", mode: FileMode.append, flush: true);
  }

  void autoCheck() {
    if (!shouldCheck) return;
    shouldCheck = false;
    if (currentPuzzle == null) return;
    final failedConstraints = currentPuzzle!.check();
    if (failedConstraints.isEmpty) {
      if (currentPuzzle!.complete) {
        final stat = currentPuzzle!.stats.stop(
          currentPuzzle!.lineRepresentation,
        );
        stats.add(stat);
        writeStat(stat);
        loadPuzzle();
      }
    } else {
      currentPuzzle!.stats.failures += 1;
    }
    setState(() {
      topMessage = failedConstraints.isNotEmpty
          ? "Some constraints are not valid."
          : "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.undo_outlined),
            tooltip: "Undo",
            onPressed: undo,
          ),
          IconButton(
            icon: Icon(Icons.fiber_new),
            tooltip: "New",
            onPressed: loadPuzzle,
          ),
          Open(
            puzzles: unsolvedPuzzles,
            solvedPuzzles: [],
            onPuzzleSelected: (puz) => openPuzzle(puz),
          ),
          IconButton(
            icon: Icon(Icons.restart_alt_rounded),
            tooltip: "Restart",
            onPressed: restartPuzzle,
          ),
          StatsBtn(stats: stats),
          Help(),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 2,
          children: <Widget>[
            Text(topMessage),
            (currentPuzzle != null)
                ? PuzzleWidget(
                    currentPuzzle: currentPuzzle!,
                    onCellTap: handlePuzzleTap,
                  )
                : Text("No puzzle loaded."),

            DecoratedBox(
              decoration: BoxDecoration(color: Colors.amber),
              child: Row(
                spacing: 2,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    margin: EdgeInsets.all(4),
                    child: Text(bottomMessage),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
