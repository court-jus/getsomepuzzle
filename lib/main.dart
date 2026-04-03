// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/between_puzzles.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/create_page.dart';
import 'package:getsomepuzzle/widgets/generate_page.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:getsomepuzzle/widgets/settings_page.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const versionText = "Version 1.4.2";

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
  String topMessage = "";
  Color topMessageColor = Colors.black;
  List<Widget> bottomMessage = [];
  PuzzleData? currentMeta;
  Puzzle? currentPuzzle;
  Database? database;
  Settings settings = Settings();
  bool shouldCheck = false;
  List<int> history = [];
  int dbSize = 0;
  bool paused = false;
  bool betweenPuzzles = false;
  bool initialized = false;
  bool shouldChooseLocale = true;
  Move? helpMove;
  String hintText = "";
  bool hintIsError = false;
  int? firstDragValue;
  int? lastDragIdx;
  bool _testingFromEditor = false;
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
        bottomMessage = [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${currentPuzzle!.width}x${currentPuzzle!.height} (${currentPuzzle!.width * currentPuzzle!.height}) "),
              FaIcon(FontAwesomeIcons.brain, size: 12),
              Text(" ${currentMeta!.cplx}"),
            ],
          ),
          Text(currentMeta!.stats.toString()),
          Text("$dbSize"),
        ];
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
    futures.add(settings.load());
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

  void setTopMessage({String text = "", Color color = Colors.black}) {
    setState(() {
      topMessage = text;
      topMessageColor = color;
    });
  }

  void loadPuzzle({bool skipped = false}) async {
    if (database == null) return;
    if (currentMeta != null && skipped) {
      currentMeta!.skipped = DateTime.now();
    }
    final nextPuzzle = database!.next();
    log.fine("Found ${nextPuzzle?.lineRepresentation}");
    if (nextPuzzle != null) {
      openPuzzle(nextPuzzle);
    } else {
      setState(() {
        currentPuzzle = null;
        history = [];
        betweenPuzzles = false;
      });
    }
  }

  void openPuzzle(PuzzleData puz) {
    setState(() {
      dbSize = database!.playlist.length;

      currentMeta = puz;
      currentPuzzle = currentMeta!.begin();
      paused = false;
      betweenPuzzles = false;
      hintText = "";
      helpMe();
    });
  }

  void _openCreatePage() {
    setState(() => _testingFromEditor = false);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => CreatePage(
          database: database!,
          onPuzzleSelected: openPuzzle,
          onTestStarted: () {
            setState(() => _testingFromEditor = true);
          },
        ),
      ),
    );
  }

  void restartPuzzle() {
    if (currentPuzzle == null) return;
    setState(() {
      setTopMessage();
      topMessageColor = Colors.black;
      history = [];
      betweenPuzzles = false;
      hintText = "";
      currentPuzzle!.restart();
      currentPuzzle!.clearConstraintsValidity();
      currentPuzzle!.clearHighlights();
      betweenPuzzles = false;
      helpMe();
    });
  }

  void undo() {
    if (currentPuzzle == null || history.isEmpty) return;
    setState(() {
      betweenPuzzles = false;
      hintText = "";
      currentPuzzle!.resetCell(history.removeLast());
      currentPuzzle!.clearConstraintsValidity();
      currentPuzzle!.clearHighlights();
      setTopMessage();
      betweenPuzzles = false;
      helpMe();
    });
  }

  Future<void> helpMe() async {
    if (currentPuzzle == null) return;
    helpMove = currentPuzzle!.findAMove();
  }

  String _constraintName(Constraint constraint) {
    final l10n = AppLocalizations.of(context)!;
    if (constraint is ForbiddenMotif) return l10n.constraintForbiddenPattern;
    if (constraint is GroupSize) return l10n.constraintGroupSize;
    if (constraint is LetterGroup) return l10n.constraintLetterGroup;
    if (constraint is ParityConstraint) return l10n.constraintParity;
    if (constraint is QuantityConstraint) return l10n.constraintQuantity;
    if (constraint is SymmetryConstraint) return l10n.constraintSymmetry;
    return "";
  }

  void showHelpMove() {
    if (helpMove == null) return;
    setState(() {
      currentPuzzle!.clearHighlights();
      if (helpMove!.isImpossible != null) {
        helpMove!.isImpossible!.isValid = false;
        hintText = AppLocalizations.of(context)!.hintImpossible;
        hintIsError = true;
      } else {
        helpMove!.givenBy.isHighlighted = true;
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
        hintText = AppLocalizations.of(context)!.hintDeducedFrom(
          _constraintName(helpMove!.givenBy),
        );
        hintIsError = false;
      }
    });
  }

  void handleCheck() {
    if (settings.liveCheckType == LiveCheckType.all ||
        settings.liveCheckType == LiveCheckType.count) {
      shouldCheck = true;
      autoCheck();
      return;
    }
    if (settings.validateType == ValidateType.manual) return;
    shouldCheck = currentPuzzle!.complete;
    if (shouldCheck) {
      Future.delayed(Duration(seconds: 1), autoCheck);
    }
  }

  void handlePuzzleTap(int idx) {
    if (currentPuzzle == null) return;
    if (currentPuzzle!.cells[idx].readonly) {
      return;
    }
    currentPuzzle!.clearHighlights();
    setState(() {
      hintText = "";
      currentPuzzle!.incrValue(idx);
      currentPuzzle!.clearConstraintsValidity();
      helpMove = null;
      helpMe();
      if (history.isEmpty || history.last != idx) history.add(idx);
      handleCheck();
    });
  }

  void handlePuzzleDrag(int idx) {
    if (currentPuzzle == null) return;
    if (idx < 0 || idx >= currentPuzzle!.cells.length) return;
    if (lastDragIdx != null && idx == lastDragIdx) return;
    setState(() {
      lastDragIdx = idx;
      if (firstDragValue == null) {
        final myOpposite = currentPuzzle!.domain
            .whereNot((e) => e == currentPuzzle!.cellValues[idx])
            .first;
        firstDragValue = myOpposite;
        currentPuzzle!.setValue(idx, firstDragValue!);
        if (history.isEmpty || history.last != idx) history.add(idx);
      }
      if (currentPuzzle!.cellValues[idx] != firstDragValue &&
          currentPuzzle!.cellValues[idx] == 0) {
        currentPuzzle!.setValue(idx, firstDragValue!);
        if (history.isEmpty || history.last != idx) history.add(idx);
      }
    });
  }

  void handlePuzzleDragEnd() {
    setState(() {
      firstDragValue = null;
      lastDragIdx = null;
      handleCheck();
    });
  }

  void autoCheck() {
    if (!shouldCheck) return;
    shouldCheck = false;
    if (currentPuzzle == null) return;
    checkPuzzle();
  }

  void checkPuzzle({bool manualCheck = false}) {
    final shouldShowErrors =
        settings.liveCheckType == LiveCheckType.all || currentPuzzle!.complete;
    final failedConstraints = currentPuzzle!.check(
      saveResult: shouldShowErrors,
    );
    if (failedConstraints.isEmpty) {
      if (currentPuzzle!.complete &&
          (manualCheck || settings.validateType != ValidateType.manual)) {
        currentMeta!.stop();
        postMessage(
          "played",
          jsonEncode({"puzzle": currentMeta!.lineRepresentation}),
          settings.shareData,
        );
        setState(() {
          if (settings.showRating == ShowRating.yes) {
            betweenPuzzles = true;
          } else {
            loadPuzzle();
          }
        });
      }
    } else if (settings.liveCheckType == LiveCheckType.complete) {
      currentMeta!.failures += 1;
      currentMeta!.stats?.failures += 1;
    }
    setState(() {
      if (failedConstraints.isNotEmpty) {
        if (shouldShowErrors) {
          setTopMessage(
            text: "Some constraints are not valid.",
            color: Colors.red,
          );
        } else {
          setTopMessage(
            text: "${failedConstraints.length} errors.",
            color: Colors.red,
          );
        }
      } else {
        setTopMessage();
      }
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

  void like(int liked) {
    if (currentMeta == null) return;
    currentMeta!.pleasure = liked;
    postMessage(
      "like",
      jsonEncode({"puzzle": currentMeta!.lineRepresentation, "liked": liked}),
      settings.shareData,
    );
    if (liked > 0) {
      currentMeta!.liked = DateTime.now();
    } else if (liked < 0) {
      currentMeta!.disliked = DateTime.now();
    }
    loadPuzzle();
  }

  void report() {
    if (currentMeta == null) return;
    postMessage(
      "report",
      jsonEncode({"puzzle": currentMeta!.lineRepresentation}),
      settings.shareData,
    );
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
          if (_testingFromEditor && database != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: AppLocalizations.of(context)!.create,
              onPressed: _openCreatePage,
            ),
          if (currentPuzzle != null &&
              !shouldChooseLocale &&
              settings.validateType == ValidateType.manual)
            Tooltip(
              message: AppLocalizations.of(context)!.manuallyValidatePuzzle,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Colors.lightGreen,
                  disabledBackgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceDim,
                  disabledForegroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryFixedDim,
                  // tooltip: AppLocalizations.of(context)!.manuallyValidatePuzzle,
                ),
                onPressed: (currentPuzzle!.complete && !betweenPuzzles)
                    ? () => checkPuzzle(manualCheck: true)
                    : null,
                icon: const Icon(Icons.check),
                label: Text(
                  AppLocalizations.of(context)!.manuallyValidatePuzzle,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.lightbulb),
              tooltip: AppLocalizations.of(context)!.tooltipClue,
              onPressed: helpMove == null ? null : showHelpMove,
            ),
          if (currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.undo_outlined),
              tooltip: AppLocalizations.of(context)!.tooltipUndo,
              onPressed: history.isEmpty ? null : undo,
            ),
          if (currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.restart_alt_outlined),
              tooltip: AppLocalizations.of(context)!.restart,
              onPressed: history.isEmpty ? null : restartPuzzle,
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
            ListTile(
              leading: Icon(Icons.close),
              title: Text(AppLocalizations.of(context)!.closeMenu),
              onTap: () {
                loadPuzzle();
                Navigator.pop(context);
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.bug_report),
              title: Text(AppLocalizations.of(context)!.report),
              onTap: () {
                report();
                Navigator.pop(context);
              },
            ),
            Divider(),
            if (database != null)
              ListTile(
                leading: Icon(Icons.fiber_new),
                title: Text(AppLocalizations.of(context)!.newgame),
                onTap: () {
                  loadPuzzle(skipped: true);
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
                leading: Icon(Icons.auto_fix_high),
                title: Text(AppLocalizations.of(context)!.generate),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => GeneratePage(
                        database: database!,
                        onPuzzleSelected: openPuzzle,
                      ),
                    ),
                  );
                },
              ),
            if (database != null)
              ListTile(
                leading: Icon(Icons.edit),
                title: Text(AppLocalizations.of(context)!.create),
                onTap: () {
                  Navigator.pop(context);
                  _openCreatePage();
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
              leading: Icon(Icons.settings),
              title: Text(AppLocalizations.of(context)!.settings),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(
                      settings: settings,
                      onSettingsChange: settings.change,
                    ),
                  ),
                );
              },
            ),
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
              Text(
                topMessage,
                style: TextStyle(
                  fontSize: 16,
                  color: topMessageColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              (initialized && !shouldChooseLocale)
                  ? Stack(
                      alignment: AlignmentGeometry.center,
                      children: [
                        if (betweenPuzzles)
                          Column(
                            spacing: 16,
                            children: [
                              if (betweenPuzzles)
                                BetweenPuzzles(
                                  like: like,
                                  loadPuzzle: loadPuzzle,
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
                                        child: Icon(
                                          Icons.pause,
                                          size: cellSize * 3,
                                        ),
                                      ),
                                    ),
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
                              if (currentPuzzle != null)
                                PuzzleWidget(
                                  currentPuzzle: currentPuzzle!,
                                  onCellTap: handlePuzzleTap,
                                  onCellDrag: handlePuzzleDrag,
                                  onCellDragEnd: handlePuzzleDragEnd,
                                  cellSize: cellSize,
                                  locale: locale,
                                  hintText: hintText,
                                  hintIsError: hintIsError,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: bottomMessage,
              ),
            )
          : null,
    );
  }
}

Future<http.Response?> postMessage(
  String endpoint,
  String body,
  ShareData share,
) async {
  if (share == ShareData.no) return null;
  final log = Logger("Network");
  log.info("Posting message $endpoint with data $body");
  try {
    return await http.post(
      Uri.parse("https://getsomepuzzle.court-jus.net:444/$endpoint/"),
      headers: <String, String>{
        "Content-type": "application/json; charset=UTF-8",
      },
      body: body,
    );
  } on http.ClientException catch (err) {
    log.severe("Client could not connect $err");
    return null;
  } catch (err) {
    log.severe("Unkown exception while connecting $err");
    return null;
  }
}
