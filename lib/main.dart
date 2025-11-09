// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/more_menu.dart';
import 'package:getsomepuzzle/widgets/pause_menu.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';

import 'getsomepuzzle/puzzle.dart';

void main() {
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
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
  final log = Logger("HomePage");

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    initializeDatabase();
    Timer.periodic(Duration(seconds: 1), (tmr) {
      if (database == null) return;
      if (currentPuzzle == null) return;
      setState(() {
        String statsText = currentMeta!.stats.toString();
        bottomMessage = "$dbSize - $statsText";
      });
    });
    Timer.periodic(Duration(seconds: 60), (tmr) {
      if (database == null) return;
      database!.writeStats();
    });
  }

  Future<void> initializeDatabase() async {
    final db = Database();
    await db.loadPuzzlesFile();
    setState(() {
      database = db;
      loadPuzzle();
    });
  }

  void loadPuzzle() async {
    if (database == null) return;
    final nextPuzzle = database!.next();
    log.fine("Found ${nextPuzzle?.lineRepresentation}");
    if (nextPuzzle != null) {
      openPuzzle(nextPuzzle);
    } else {
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
                        child: Icon(Icons.skip_next, size: 96),
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
