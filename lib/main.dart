// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/between_puzzles.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/create_page.dart';
import 'package:getsomepuzzle/widgets/generate_page.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:getsomepuzzle/widgets/settings_page.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';
import 'package:getsomepuzzle/widgets/timer_bottom_bar.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const versionText = "Version 1.5.2";

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
  final ValueChanged<String> setAppLocale;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GameModel game = GameModel();
  String locale = "en";
  Database? database;
  Settings settings = Settings();
  bool initialized = false;
  bool shouldChooseLocale = true;
  bool _testingFromEditor = false;
  Timer? _saveTimer;
  final log = Logger("HomePage");

  @override
  void initState() {
    super.initState();
    // Prevent screen sleep
    if (!kIsWeb && Platform.isAndroid) {
      WakelockPlus.enable();
    }
    game.addListener(() {
      if (mounted) setState(() {});
    });
    initialize();
    _saveTimer = Timer.periodic(const Duration(seconds: 60), (tmr) {
      if (database == null) return;
      database!.writeStats();
    });
  }

  @override
  void dispose() {
    game.dispose();
    _saveTimer?.cancel();
    super.dispose();
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

  // ---------------------------------------------------------------------------
  // Puzzle lifecycle (thin wrappers around GameModel)
  // ---------------------------------------------------------------------------

  void loadPuzzle({bool skipped = false}) {
    if (database == null) return;
    if (game.currentMeta != null && skipped) {
      game.currentMeta!.skipped = DateTime.now();
    }
    final nextPuzzle = database!.next();
    log.fine("Found ${nextPuzzle?.lineRepresentation}");
    if (nextPuzzle != null) {
      openPuzzle(nextPuzzle);
    } else {
      game.clearPuzzle();
    }
  }

  void openPuzzle(PuzzleData puz) {
    game.openPuzzle(puz, database!.playlist.length);
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

  // ---------------------------------------------------------------------------
  // Cell interaction (delegate to GameModel + side effects)
  // ---------------------------------------------------------------------------

  void handlePuzzleTap(int idx) {
    if (game.handleTap(idx)) {
      _handleCheck();
    }
  }

  void handlePuzzleDrag(int idx) {
    game.handleDrag(idx);
  }

  void handlePuzzleDragEnd() {
    game.handleDragEnd();
    _handleCheck();
  }

  void handlePuzzleRightDrag(int idx) {
    game.handleRightDrag(idx);
  }

  void handlePuzzleRightDragEnd() {
    game.handleRightDragEnd();
    _handleCheck();
  }

  // ---------------------------------------------------------------------------
  // Check / validation
  // ---------------------------------------------------------------------------

  void _handleCheck() {
    game.handleCheck(settings, onPuzzleCompleted: _onPuzzleCompleted);
  }

  void _onPuzzleCompleted() {
    postMessage(
      "played",
      jsonEncode({"puzzle": game.currentMeta!.lineRepresentation}),
      settings.shareData,
    );
    if (settings.showRating != ShowRating.yes) {
      loadPuzzle();
    }
  }

  // ---------------------------------------------------------------------------
  // Pause / resume
  // ---------------------------------------------------------------------------

  void togglePause() {
    if (game.paused) {
      game.resume();
      if (game.currentPuzzle == null) {
        loadPuzzle();
      }
    } else {
      game.pause();
    }
  }

  // ---------------------------------------------------------------------------
  // Hint (l10n resolved here, state mutation in GameModel)
  // ---------------------------------------------------------------------------

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
    if (game.helpMove == null) return;
    if (game.hintText.isNotEmpty && !game.hintIsError) {
      game.showHelpMove("");
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    String resolvedHintText;
    if (game.helpMove!.isImpossible != null) {
      resolvedHintText = l10n.hintImpossible;
    } else if (game.helpMove!.isForce) {
      resolvedHintText = l10n.hintForce;
    } else {
      resolvedHintText = l10n.hintDeducedFrom(
        _constraintName(game.helpMove!.givenBy),
      );
    }
    game.showHelpMove(resolvedHintText);
  }

  // ---------------------------------------------------------------------------
  // Rating & report
  // ---------------------------------------------------------------------------

  void like(int liked) {
    if (game.currentMeta == null) return;
    game.like(liked);
    postMessage(
      "like",
      jsonEncode({
        "puzzle": game.currentMeta!.lineRepresentation,
        "liked": liked,
      }),
      settings.shareData,
    );
    loadPuzzle();
  }

  void report() {
    if (game.currentMeta == null) return;
    postMessage(
      "report",
      jsonEncode({"puzzle": game.currentMeta!.lineRepresentation}),
      settings.shareData,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
    if (game.currentPuzzle != null) {
      double maxWidth = contextWidth / game.currentPuzzle!.width;
      double maxHeight = contextHeight / (game.currentPuzzle!.height + 2);
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
          if (game.currentPuzzle != null &&
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
                ),
                onPressed:
                    (game.currentPuzzle!.complete && !game.betweenPuzzles)
                    ? () => game.checkPuzzle(
                        settings,
                        manualCheck: true,
                        onPuzzleCompleted: _onPuzzleCompleted,
                      )
                    : null,
                icon: const Icon(Icons.check),
                label: Text(
                  AppLocalizations.of(context)!.manuallyValidatePuzzle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (game.currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.lightbulb),
              tooltip: AppLocalizations.of(context)!.tooltipClue,
              onPressed: game.helpMove == null ? null : showHelpMove,
            ),
          if (game.currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.undo_outlined),
              tooltip: AppLocalizations.of(context)!.tooltipUndo,
              onPressed: game.history.isEmpty ? null : game.undo,
            ),
          if (game.currentPuzzle != null && !shouldChooseLocale)
            IconButton(
              icon: Icon(Icons.restart_alt_outlined),
              tooltip: AppLocalizations.of(context)!.restart,
              onPressed: game.history.isEmpty ? null : game.restart,
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
                  Text(widget.title, style: const TextStyle(fontSize: 24)),
                  Text(versionText),
                  const SizedBox(height: 10),
                  Text('Ghislain "court-jus" Lévêque'),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.close),
              title: Text(AppLocalizations.of(context)!.closeMenu),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.bug_report),
              title: Text(AppLocalizations.of(context)!.report),
              onTap: () {
                report();
                Navigator.pop(context);
              },
            ),
            const Divider(),
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
            const Divider(),
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
                      onSettingsChange: (newValue) {
                        settings.change(newValue);
                        game.refresh();
                      },
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
                game.topMessage,
                style: TextStyle(
                  fontSize: 16,
                  color: game.topMessageColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              (initialized && !shouldChooseLocale)
                  ? Stack(
                      alignment: AlignmentGeometry.center,
                      children: [
                        if (game.betweenPuzzles)
                          BetweenPuzzles(like: like, loadPuzzle: loadPuzzle)
                        else if (game.paused)
                          PauseOverlay(
                            onResume: togglePause,
                            width: contextWidth,
                            height: contextHeight,
                            iconSize: cellSize * 3,
                          )
                        else
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (game.currentPuzzle != null)
                                PuzzleWidget(
                                  currentPuzzle: game.currentPuzzle!,
                                  onCellTap: handlePuzzleTap,
                                  onCellDrag: handlePuzzleDrag,
                                  onCellDragEnd: handlePuzzleDragEnd,
                                  onCellRightDrag: isDesktopOrWeb
                                      ? handlePuzzleRightDrag
                                      : null,
                                  onCellRightDragEnd: isDesktopOrWeb
                                      ? handlePuzzleRightDragEnd
                                      : null,
                                  cellSize: cellSize,
                                  locale: locale,
                                  hintText: game.hintText,
                                  hintIsError: game.hintIsError,
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
                        ? InitialLocaleChooser(selectLocale: toggleLocale)
                        : Text("Loading...")),
            ],
          ),
        ),
      ),
      bottomNavigationBar: (initialized && !shouldChooseLocale)
          ? TimerBottomBar(
              currentMeta: game.currentMeta,
              currentPuzzle: game.currentPuzzle,
              dbSize: game.dbSize,
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
