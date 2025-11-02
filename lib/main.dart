// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
  bool paused = false;
  bool betweenPuzzles = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    loadStats();
    Timer.periodic(Duration(seconds: 1), (tmr) {
      if (database == null) return;
      if (currentPuzzle == null) return;
      setState(() {
        String statsText = currentMeta!.stats.toString();
        bottomMessage = "$dbSize - $statsText";
      });
    });
    Timer.periodic(Duration(seconds: 10), (tmr) {
      if (database == null) return;
      final List<String> stats = database!.getStats();
      writeStats(stats);
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
        print("Stats file does not exist");
        file.createSync();
      }
      final content = await file.readAsString();
      stats.addAll(content.split("\n"));
    }
    print("Stats to load $stats");
    db.loadStats(stats);
    setState(() {
      database = db;
      loadPuzzle();
    });
  }

  void loadPuzzle() async {
    if (database == null) return;
    final randomPuzzle = database!.next();
    developer.log("Found ${randomPuzzle?.lineRepresentation}");
    if (randomPuzzle != null) {
      openPuzzle(randomPuzzle);
    } else {
      developer.log("bah non");
      setState(() {
        currentPuzzle = null;
        betweenPuzzles = false;
      });
    }
  }

  void openPuzzle(PuzzleData puz) {
    setState(() {
      Iterable<PuzzleData> db = database!.filter();
      dbSize = db.length;

      currentMeta = puz;
      currentPuzzle = currentMeta!.begin();
      paused = false;
      betweenPuzzles = false;
      topMessage = "";
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

  Future<void> writeStats(List<String> stats) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('stats', stats);
      return;
    }
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDirectory.path, "getsomepuzzle");
    await Directory(path).create(recursive: true);
    final filePath = p.join(path, "stats.txt");
    print("filePath $filePath");
    final file = File(filePath);

    file.writeAsStringSync(
      stats.join("\n"),
      mode: FileMode.writeOnly,
      flush: true,
    );
  }

  void autoCheck() {
    if (!shouldCheck) return;
    shouldCheck = false;
    if (currentPuzzle == null) return;
    final failedConstraints = currentPuzzle!.check();
    if (failedConstraints.isEmpty) {
      if (currentPuzzle!.complete) {
        currentMeta!.stop();
        setState(() {
          betweenPuzzles = true;
        });
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

  void pause() {
    setState(() {
      paused = true;
      if (currentPuzzle != null) {
        currentMeta!.stats?.pause();
      }
    });
  }

  void resume() {
    setState(() {
      paused = false;
      if (currentPuzzle == null) {
        loadPuzzle();
      } else {
        currentMeta!.stats?.resume();
      }
    });
  }

  void togglePause() {
    if (paused) {
      resume();
    } else {
      pause();
    }
  }

  void like(bool liked) {
    if (currentMeta == null) return;
    if (liked) {
      currentMeta!.liked = DateTime.now();
    } else {
      currentMeta!.disliked = DateTime.now();
    }
    loadPuzzle();
  }

  @override
  Widget build(BuildContext context) {
    double contextWidth = MediaQuery.sizeOf(context).width;
    double contextHeight =
        (MediaQuery.sizeOf(context).height -
        40 - // The bottom bar
        64 - // The app bar
        128  // Some margin
        );
    double cellSize = 32.0;
    if (currentPuzzle != null) {
      double maxWidth = contextWidth / currentPuzzle!.width;
      double maxHeight = contextHeight / (currentPuzzle!.height + 2);
      cellSize = min(maxWidth, maxHeight);
    }

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
                if (betweenPuzzles)
                  Column(
                    spacing: 16,
                    children: [
                      Text("Puzzle solved!", style: TextStyle(fontSize: 48)),
                      Text(
                        "Was it fun to play?",
                        style: TextStyle(fontSize: 24),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        spacing: 16,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              minimumSize: Size(cellSize, cellSize),
                              maximumSize: Size(cellSize * 2, cellSize * 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadiusGeometry.circular(16),
                              ),
                            ),
                            onPressed: () => like(true),
                            child: const Icon(Icons.thumb_up, size: 96),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent[100],
                              minimumSize: Size(cellSize, cellSize),
                              maximumSize: Size(cellSize * 2, cellSize * 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadiusGeometry.circular(16),
                              ),
                            ),
                            onPressed: () => like(false),
                            child: const Icon(Icons.thumb_down, size: 96),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlueAccent[100],
                              minimumSize: Size(cellSize * 2, cellSize),
                              maximumSize: Size(cellSize * 2, cellSize * 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadiusGeometry.circular(16),
                          ),
                        ),
                        onPressed: loadPuzzle,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Next", style: TextStyle(fontSize: 40)),
                            Icon(Icons.skip_next, size: 96),
                          ],
                        ),
                      ),
                    ],
                  )
                else if (paused)
                  TextButton(
                    onPressed: resume,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: SizedBox(
                        width: contextWidth,
                        height: contextHeight,
                        child: Center(
                          child: Icon(Icons.pause, size: cellSize * 3),
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      (currentPuzzle != null)
                          ? PuzzleWidget(
                              currentPuzzle: currentPuzzle!,
                              onCellTap: handlePuzzleTap,
                              cellSize: cellSize,
                            )
                          : Text("No puzzle loaded."),
                    ],
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
