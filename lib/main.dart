// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/more_menu.dart';
import 'package:getsomepuzzle/widgets/pause_menu.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
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
  PuzzleData? currentMeta;
  Puzzle? currentPuzzle;
  Database? database;
  bool shouldCheck = false;
  List<int> history = [];
  int dbSize = 0;
  int playedCount = 0;
  bool paused = false;

  @override
  void initState() {
    super.initState();
    loadStats();
    Timer.periodic(Duration(seconds: 1), (tmr) {
      if (database == null) return;
      if (currentPuzzle == null) return;
      setState(() {
        String statsText = currentMeta!.stats.toString();
        bottomMessage = "$playedCount/$dbSize - $statsText";
      });
    });
  }

  Future<void> loadStats() async {
    final db = Database();
    await db.loadPuzzlesFile();
    await db.currentFilters.load();
    final List<String> stats = [];
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      stats.addAll(prefs.getStringList('stats') ?? []);
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
      stats.addAll(content.split("\n"));
    }
    db.loadStats(stats);
    setState(() {
      database = db;
      loadPuzzle();
    });
  }

  void loadPuzzle() async {
    if (database == null) return;
    final randomPuzzle = database!.next();
    if (randomPuzzle != null) {
      openPuzzle(randomPuzzle);
    }
  }

  void openPuzzle(PuzzleData puz) {
    setState(() {
      Iterable<PuzzleData> db = database!.filter();
      playedCount = db.where((puz) => puz.played).length;
      dbSize = db.length;

      currentMeta = puz;
      currentPuzzle = currentMeta!.begin();
      paused = false;
    });
  }

  void restartPuzzle() {
    if (currentPuzzle == null) return;
    setState(() {
      topMessage = "";
      history = [];
      currentPuzzle!.restart();
      currentPuzzle!.clearConstraintsValidity();
    });
  }

  void undo() {
    if (currentPuzzle == null || history.isEmpty) return;
    setState(() {
      currentPuzzle!.resetCell(history.removeLast());
      currentPuzzle!.clearConstraintsValidity();
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
      final data = prefs.getStringList("stats") ?? [];
      data.add(text);
      await prefs.setStringList('stats', data);
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
        final stat = currentMeta!.stop();

        // stats.add(stat);
        writeStat(stat);
        loadPuzzle();
      }
    } else {
      currentMeta!.failures += 1;
      currentMeta!.stats?.failures += 1;
    }
    setState(() {
      topMessage = failedConstraints.isNotEmpty
          ? "Some constraints are not valid."
          : "";
    });
  }

  void onPause() {
    setState(() {
      paused = true;
      if (currentPuzzle != null) {
        currentMeta!.stats?.pause();
      }
    });
  }

  void onResume() {
    setState(() {
      paused = false;
      if (currentPuzzle != null) {
        currentMeta!.stats?.resume();
      }
    });
  }

  void togglePause() {
    if (paused) {
      onResume();
    } else {
      onPause();
    }
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
          if (database != null)
            MenuAnchorPause(
              database: database!,
              togglePause: togglePause,
              newPuzzle: loadPuzzle,
              selectPuzzle: openPuzzle,
              restartPuzzle: restartPuzzle,
            ),
          if (database != null)
            MenuAnchorMore(database: database!, togglePause: togglePause),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 2,
          children: <Widget>[
            Text(topMessage),
            Stack(
              alignment: AlignmentGeometry.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    (currentPuzzle != null)
                        ? PuzzleWidget(
                            currentPuzzle: currentPuzzle!,
                            onCellTap: handlePuzzleTap,
                          )
                        : Text("No puzzle loaded."),
                  ],
                ),
                if (paused)
                  TextButton(
                    onPressed: onResume,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: SizedBox(
                        width: 64 * 6,
                        height: 64 * 8,
                        child: Center(
                          child: Text("Paused", style: TextStyle(fontSize: 92)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 40,
        color: Colors.amber,
        child: Center(child: Text(bottomMessage)),
      ),
    );
  }
}
