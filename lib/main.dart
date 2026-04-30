// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/between_puzzles.dart';
import 'package:getsomepuzzle/widgets/end_of_playlist.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/create_page/create_page.dart';
import 'package:getsomepuzzle/widgets/generate_page.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:getsomepuzzle/widgets/save_progress_dialog.dart';
import 'package:getsomepuzzle/widgets/settings_page.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';
import 'package:getsomepuzzle/widgets/timer_bottom_bar.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';
import 'package:getsomepuzzle/utils/share_link_stub.dart'
    if (dart.library.html) 'package:getsomepuzzle/utils/share_link_html.dart'
    if (dart.library.io) 'package:getsomepuzzle/utils/share_link_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const versionText = "Version 1.6.2";

/// Where the GitHub Pages web build lives. Share links target this URL with
/// a `?puzzle=<line>` query — works as a browser fallback everywhere, and
/// later as the App Links / Universal Links target on mobile when set up.
const kShareBaseUrl = 'https://court-jus.github.io/getsomepuzzle/';

/// Extract a puzzle line passed at startup, either via web URL
/// (`?puzzle=v2_...`) or as a desktop CLI argument (raw `v2_...` line, or
/// any URL embedding `?puzzle=...`). Returns null if no line was found or
/// the input doesn't parse — the caller falls back to the playlist.
///
/// Top-level (and not behind kIsWeb) so it can be unit-tested by injecting
/// a synthetic [args] list.
String? parseSharedPuzzleLine(List<String> args, {Uri? webUri}) {
  final candidates = <String>[];
  // Web: query of the loaded URL.
  final fromWeb = webUri?.queryParameters['puzzle'];
  if (fromWeb != null && fromWeb.isNotEmpty) candidates.add(fromWeb);
  // Native: first CLI arg, accepted as raw line or URL.
  if (args.isNotEmpty) {
    final arg = args.first;
    if (arg.startsWith('v2_')) {
      candidates.add(arg);
    } else {
      try {
        final fromArg = Uri.parse(arg).queryParameters['puzzle'];
        if (fromArg != null && fromArg.isNotEmpty) candidates.add(fromArg);
      } catch (_) {}
    }
  }
  for (final c in candidates) {
    if (c.startsWith('v2_')) return c;
  }
  return null;
}

void main(List<String> args) {
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  final shared = parseSharedPuzzleLine(args, webUri: kIsWeb ? Uri.base : null);
  runApp(MyApp(initialSharedLine: shared));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.initialSharedLine});

  /// Puzzle line extracted from the launch URL or CLI args, if any.
  final String? initialSharedLine;

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
      home: MyHomePage(
        title: 'Get Some Puzzle',
        setAppLocale: setAppLocale,
        initialSharedLine: widget.initialSharedLine,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.setAppLocale,
    this.initialSharedLine,
  });

  final String title;
  final ValueChanged<String> setAppLocale;

  /// Puzzle line forwarded from main(args)/Uri.base. Consumed once on first
  /// database init; subsequent loads fall back to the playlist.
  final String? initialSharedLine;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    game.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (game.currentPuzzle == null || game.betweenPuzzles) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        game.autoPause(AutoPauseReason.focusLost);
      case AppLifecycleState.resumed:
        // Do not auto-resume: requiring an explicit click avoids the timer
        // silently ticking while the user is still getting back into it.
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> initialize() async {
    var futures = <Future>[];
    await settings.load();
    game.idleTimeoutDuration = settings.idleTimeoutDuration;
    futures.add(initializeDatabase(settings.playerLevel));
    futures.add(initializeLocale());
    await Future.wait(futures);
    initialized = true;
  }

  Future<void> initializeDatabase(int playerLevel) async {
    final db = Database(playerLevel: playerLevel);
    await db.loadPuzzlesFile();
    setState(() {
      database = db;
      // A shared-puzzle URL/CLI takes precedence over the playlist's next
      // entry. If parsing fails (malformed line), fall through silently.
      if (!_openSharedPuzzleIfAny()) {
        loadPuzzle();
      }
    });
  }

  /// Try to open the puzzle line passed via launch URL / CLI. Returns
  /// true on success so the caller can skip the regular `loadPuzzle()`.
  bool _openSharedPuzzleIfAny() {
    final line = widget.initialSharedLine;
    if (line == null || line.isEmpty) return false;
    try {
      openPuzzle(PuzzleData(line));
      return true;
    } catch (e, st) {
      log.warning('Failed to open shared puzzle: $e\n$st');
      return false;
    }
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
    game.openPuzzle(
      puz,
      database!.playlist.length,
      progressRestoredText: AppLocalizations.of(context)!.progressRestored,
    );
    if (settings.hintType == HintType.addConstraint) {
      game.startHintConstraintComputation();
    }
  }

  /// Build a share URL for the current puzzle (carrying the player's
  /// current play state) and hand it off to share_plus on mobile, or copy
  /// it to the clipboard on desktop/web. Recipients clicking the link
  /// land on the GitHub Pages web build, which parses `?puzzle=` at
  /// startup and opens the puzzle directly.
  Future<void> _sharePuzzle() async {
    if (game.currentPuzzle == null) return;
    final loc = AppLocalizations.of(context)!;
    final line = game.currentPuzzle!.lineWithPlayState();
    final url = '$kShareBaseUrl?puzzle=${Uri.encodeQueryComponent(line)}';
    final shared = await shareUrl(url);
    if (!mounted || shared) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.shareLinkCopied)));
  }

  /// Ask the player which playlist to save the in-progress puzzle to,
  /// then append the puzzle's line representation (with the trailing
  /// play-state field) to that playlist.
  Future<void> _saveProgress() async {
    if (database == null || game.currentPuzzle == null) return;
    final loc = AppLocalizations.of(context)!;
    final target = await showSaveProgressDialog(
      context: context,
      database: database!,
    );
    if (target == null) return;
    final line = game.currentPuzzle!.lineWithPlayState();
    await database!.addToPlaylist(target, line);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.progressSaved)));
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
    final l10n = AppLocalizations.of(context)!;
    game.handleCheck(
      settings,
      invalidConstraintsText: l10n.someConstraintsInvalid,
      errorsCountText: l10n.errorsCount,
      onPuzzleCompleted: _onPuzzleCompleted,
    );
  }

  void _onPuzzleCompleted() {
    postMessage(
      "played",
      jsonEncode({"puzzle": game.currentMeta!.lineRepresentation}),
      settings.shareData,
    );
    if (settings.autoLevel && database != null) {
      final newLevel = database!.computePlayerLevel(
        fallback: settings.playerLevel,
      );
      if (newLevel != settings.playerLevel) {
        settings.playerLevel = newLevel;
        database!.setPlayerLevel(newLevel);
        database!.preparePlaylist();
        settings.save();
      }
    }
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

  /// Subtitle to display under the pause icon, or null for a manual pause
  /// where the user already knows why the game is paused.
  String? _pauseSubtitle(BuildContext context) {
    final reason = game.autoPauseReason;
    if (reason == null) return null;
    final l10n = AppLocalizations.of(context)!;
    switch (reason) {
      case AutoPauseReason.idle:
        return l10n.pausedDueToIdle;
      case AutoPauseReason.focusLost:
        return l10n.pausedDueToFocusLost;
    }
  }

  // ---------------------------------------------------------------------------
  // Hint (l10n resolved here, state mutation in GameModel)
  // ---------------------------------------------------------------------------

  String _constraintName(CanApply givenBy) {
    final l10n = AppLocalizations.of(context)!;
    if (givenBy is ForbiddenMotif) return l10n.constraintForbiddenPattern;
    if (givenBy is ShapeConstraint) return l10n.constraintShape;
    if (givenBy is GroupSize) return l10n.constraintGroupSize;
    if (givenBy is LetterGroup) return l10n.constraintLetterGroup;
    if (givenBy is ParityConstraint) return l10n.constraintParity;
    if (givenBy is QuantityConstraint) return l10n.constraintQuantity;
    if (givenBy is SymmetryConstraint) return l10n.constraintSymmetry;
    if (givenBy is DifferentFromConstraint) return l10n.constraintDifferentFrom;
    if (givenBy is ColumnCountConstraint) return l10n.constraintColumnCount;
    if (givenBy is GroupCountConstraint) return l10n.constraintGroupCount;
    if (givenBy is NeighborCountConstraint) return l10n.constraintNeighborCount;
    if (givenBy is EyesConstraint) return l10n.constraintEyes;
    // Complicities (and any unknown source): fall back to serialize() so
    // the player sees something like "LTFMComplicity" rather than empty.
    return givenBy.serialize();
  }

  HintTexts _buildHintTexts() {
    final l10n = AppLocalizations.of(context)!;
    return HintTexts(
      someConstraintsInvalid: l10n.someConstraintsInvalid,
      hintCellWrong: l10n.hintCellWrong,
      hintAllCorrectSoFar: l10n.hintAllCorrectSoFar,
      hintCellDeducible: l10n.hintCellDeducible,
      hintImpossible: l10n.hintImpossible,
      hintForce: l10n.hintForce,
      hintDeducedFrom: (c) => l10n.hintDeducedFrom(_constraintName(c)),
      hintConstraintAdded: l10n.hintConstraintAdded,
      hintConstraintNone: l10n.hintConstraintNone,
    );
  }

  void showHelpMove() {
    game.onHintTap(settings, _buildHintTexts());
  }

  void _onHintTypeChanged() {
    if (game.currentPuzzle == null) return;
    // Force a clean cycle: a stage from the previous mode would be confusing
    // (e.g. "stage 2 = cell shown" doesn't exist in addConstraint).
    game.resetHintCycle();
    if (settings.hintType == HintType.addConstraint) {
      game.startHintConstraintComputation();
    } else {
      game.cancelHintConstraintComputation();
    }
  }

  bool _isHintButtonEnabled() {
    // Tap 1 of the hint flow must always be available so the player can
    // surface errors / "all correct" feedback regardless of mode.
    return game.currentPuzzle != null;
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
                        invalidConstraintsText: AppLocalizations.of(
                          context,
                        )!.someConstraintsInvalid,
                        errorsCountText: AppLocalizations.of(
                          context,
                        )!.errorsCount,
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
              onPressed: _isHintButtonEnabled() ? showHelpMove : null,
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
            if (database != null && game.currentPuzzle != null)
              ListTile(
                leading: Icon(Icons.save_outlined),
                title: Text(AppLocalizations.of(context)!.saveProgress),
                onTap: () {
                  Navigator.pop(context);
                  _saveProgress();
                },
              ),
            if (database != null && game.currentPuzzle != null)
              ListTile(
                leading: Icon(Icons.share_outlined),
                title: Text(AppLocalizations.of(context)!.sharePuzzle),
                onTap: () {
                  Navigator.pop(context);
                  _sharePuzzle();
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
                      onRestartTutorial: () async {
                        if (database == null) return;
                        await database!.restartTutorial();
                        // Switch to the tutorial collection (reloads puzzles
                        // + stats + playlist) and open the first puzzle.
                        await database!.loadPuzzlesFile('tutorial');
                        game.clearPuzzle();
                        loadPuzzle();
                        setState(() {});
                      },
                      onClearStats: () async {
                        if (database == null) return;
                        await database!.clearAllStats();
                        // Drop any in-progress puzzle so the next puzzle is
                        // picked from the freshly empty playlist; without
                        // this, the player would be stuck on whatever was
                        // currently displayed (now flagged unplayed again
                        // but still selected as `current`).
                        game.clearPuzzle();
                        loadPuzzle();
                        setState(() {});
                      },
                      onSettingsChange: (newValue) {
                        final autoLevelTurnedOn =
                            newValue.autoLevel == true && !settings.autoLevel;
                        var levelChanged =
                            (newValue.playerLevel != null &&
                            newValue.playerLevel != settings.playerLevel);
                        settings.change(newValue);
                        if (newValue.hintType != null) {
                          _onHintTypeChanged();
                        }
                        if (newValue.idleTimeout != null) {
                          game.idleTimeoutDuration =
                              settings.idleTimeoutDuration;
                          game.rearmIdleTimer();
                        }
                        // Recompute immediately when auto is toggled on, so
                        // the player doesn't have to finish a puzzle first.
                        if (autoLevelTurnedOn && database != null) {
                          final newLevel = database!.computePlayerLevel(
                            fallback: settings.playerLevel,
                          );
                          if (newLevel != settings.playerLevel) {
                            settings.playerLevel = newLevel;
                            settings.save();
                            levelChanged = true;
                          }
                        }
                        if (levelChanged) {
                          database?.setPlayerLevel(settings.playerLevel);
                          database?.preparePlaylist();
                          loadPuzzle();
                        }
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
                            subtitle: _pauseSubtitle(context),
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
                                EndOfPlaylist(
                                  currentLevel: settings.playerLevel,
                                  isTutorial:
                                      database?.collection == 'tutorial',
                                  onStartPlaying: () async {
                                    if (database == null) return;
                                    settings.change(
                                      ChangeableSettings(
                                        playerLevel: 0,
                                        autoLevel: true,
                                      ),
                                    );
                                    database!.setPlayerLevel(0);
                                    // Must be awaited before loadPuzzlesFile:
                                    // loadPuzzlesFile reads shouldShuffle from
                                    // prefs, so the flip must be persisted first.
                                    await database!.setShouldShuffle(false);
                                    await database!.loadPuzzlesFile('default');
                                    if (database!.playlist.isNotEmpty) {
                                      loadPuzzle();
                                    }
                                    setState(() {});
                                  },
                                  filtersBlocking:
                                      database?.hasUnplayedIgnoringFilters() ??
                                      false,
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
              playerLevel: settings.playerLevel,
              autoLevel: settings.autoLevel,
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
