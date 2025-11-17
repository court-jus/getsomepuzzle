// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'getsomepuzzle/puzzle.dart';
import 'l10n/app_localizations.dart';

const versionText = "Version 1.3.3";

void main() {
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale selectedLocale = Locale("en");

  void setAppLocale(String newLocale) {
    setState(() {
      selectedLocale = Locale(newLocale);
    });
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Get Some Puzzle',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: selectedLocale, // controlled by state
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MyHomePage(title: 'Get Some Puzzle', setAppLocale: setAppLocale),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.setAppLocale,
  });

  final String title;
  final Function setAppLocale;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool helpVisible = false;
  String locale = "en";
  String topMessage = versionText;
  String bottomMessage = "";
  PuzzleData? currentMeta;
  Puzzle? currentPuzzle;
  Database? database;
  bool shouldCheck = false;
  List<int> history = [];
  int dbSize = 0;
  bool paused = false;
  bool betweenPuzzles = false;
  bool initialized = false;
  bool shouldChooseLocale = true;
  final log = Logger("HomePage");

  @override
  void initState() {
    super.initState();
    // Prevent screen sleep
    if (!kIsWeb && Platform.isAndroid) {
      WakelockPlus.enable();
    }
    initialize();
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

  Future<void> initialize() async {
    var futures = <Future>[];
    futures.add(initializeDatabase());
    futures.add(initializeLocale());
    await Future.wait(futures);
    initialized = true;
  }

  Future<void> initializeDatabase() async {
    final db = Database();
    await db.loadPuzzlesFile();
    setState(() {
      database = db;
      loadPuzzle();
    });
  }

  Future<void> initializeLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final prefLocale = prefs.getString("locale");
    if (prefLocale != null && prefLocale != "") {
      shouldChooseLocale = false;
      toggleLocale(prefLocale);
    }
  }

  Future<void> saveChosenLocale(String newLocale) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("locale", newLocale);
  }

  void toggleLocale(String newLocale) {
    setState(() {
      shouldChooseLocale = false;
      locale = newLocale;
      widget.setAppLocale(locale);
    });
    saveChosenLocale(newLocale);
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
      topMessage = versionText;
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
      if (shouldCheck) {
        Future.delayed(Duration(seconds: 1), autoCheck);
      } else {
        currentPuzzle!.clearConstraintsValidity();
      }
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
        128 // Some margin
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
          if (currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.undo_outlined),
              tooltip: AppLocalizations.of(context)!.tooltipUndo,
              onPressed: undo,
            ),
          if (currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.restart_alt_outlined),
              tooltip: AppLocalizations.of(context)!.restart,
              onPressed: restartPuzzle,
            ),
          if (database != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.pause),
              tooltip: AppLocalizations.of(context)!.tooltipPause,
              onPressed: togglePause,
            ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blue),
              child: Column(
                children: [
                  Text(widget.title, style: TextStyle(fontSize: 24)),
                  Text(versionText),
                  SizedBox(height: 10),
                  Text('Ghislain "court-jus" Lévêque'),
                ],
              ),
            ),
            if (database != null)
              ListTile(
                leading: Icon(Icons.fiber_new),
                title: Text(AppLocalizations.of(context)!.newgame),
                onTap: () {
                  loadPuzzle();
                  Navigator.pop(context);
                },
              ),
            if (database != null)
              ListTile(
                leading: Icon(Icons.file_open),
                title: Text(AppLocalizations.of(context)!.open),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => OpenPage(
                        database: database!,
                        onPuzzleSelected: openPuzzle,
                      ),
                    ),
                  );
                },
              ),
            if (database != null)
              ListTile(
                leading: Icon(Icons.newspaper),
                title: Text(AppLocalizations.of(context)!.stats),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => StatsPage(database: database!),
                    ),
                  );
                },
              ),
            Divider(),
            ListTile(
              leading: Icon(Icons.help),
              title: Text(AppLocalizations.of(context)!.help),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HelpPage(locale: locale),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.language),
              title: Text(AppLocalizations.of(context)!.tooltipLanguage),
              onTap: () {
                setState(() {
                  shouldChooseLocale = true;
                  Navigator.pop(context);
                });
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 2,
            children: <Widget>[
              Text(topMessage),
              (initialized && !shouldChooseLocale)
                  ? Stack(
                      alignment: AlignmentGeometry.center,
                      children: [
                        if (betweenPuzzles)
                          Column(
                            spacing: 16,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.msgPuzzleSolved,
                                style: TextStyle(fontSize: 48),
                              ),
                              Text(
                                AppLocalizations.of(context)!.questionFunToPlay,
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
                                      maximumSize: Size(
                                        cellSize * 2,
                                        cellSize * 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadiusGeometry.circular(16),
                                      ),
                                    ),
                                    onPressed: () => like(true),
                                    child: const Icon(Icons.thumb_up, size: 96),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent[100],
                                      minimumSize: Size(cellSize, cellSize),
                                      maximumSize: Size(
                                        cellSize * 2,
                                        cellSize * 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadiusGeometry.circular(16),
                                      ),
                                    ),
                                    onPressed: () => like(false),
                                    child: const Icon(
                                      Icons.thumb_down,
                                      size: 96,
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.lightBlueAccent[100],
                                  minimumSize: Size(cellSize * 2, cellSize),
                                  maximumSize: Size(cellSize * 2, cellSize * 2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadiusGeometry.circular(
                                      16,
                                    ),
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
                              if (currentPuzzle != null)
                                PuzzleWidget(
                                  currentPuzzle: currentPuzzle!,
                                  onCellTap: handlePuzzleTap,
                                  cellSize: cellSize,
                                  locale: locale,
                                )
                              else
                                Text(
                                  AppLocalizations.of(context)!.infoNoPuzzle,
                                ),
                            ],
                          ),
                      ],
                    )
                  : (shouldChooseLocale
                        ? Initiallocalechooser(selectLocale: toggleLocale)
                        : Text("Loading...")),
            ],
          ),
        ),
      ),
      bottomNavigationBar: (initialized && !shouldChooseLocale)
          ? BottomAppBar(
              height: 40,
              color: Colors.amber,
              child: Center(child: Text(bottomMessage)),
            )
          : null,
    );
  }
}
