// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' show exit;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:getsomepuzzle/getsomepuzzle/autopilot/autopilot.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/autopilot_state.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/end_of_playlist.dart';
import 'package:getsomepuzzle/widgets/fake_cursor.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/learning_page.dart';
import 'package:getsomepuzzle/widgets/main_drawer.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';
import 'package:getsomepuzzle/widgets/onboarding_complete_dialog.dart';
import 'package:getsomepuzzle/widgets/third_color_suggestion_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/create_page.dart';
import 'package:getsomepuzzle/widgets/generate_page.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
import 'package:getsomepuzzle/widgets/autopilot_dialog.dart';
import 'package:getsomepuzzle/widgets/between_puzzles.dart';
import 'package:getsomepuzzle/widgets/constraint_help_dialog.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:getsomepuzzle/widgets/save_progress_dialog.dart';
import 'package:getsomepuzzle/widgets/settings_page.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';
import 'package:getsomepuzzle/widgets/welcome_dialog.dart';
import 'package:getsomepuzzle/widgets/timer_bottom_bar.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';
import 'package:getsomepuzzle/utils/share_link_stub.dart'
    if (dart.library.html) 'package:getsomepuzzle/utils/share_link_html.dart'
    if (dart.library.io) 'package:getsomepuzzle/utils/share_link_io.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const versionText = "Version 2.0.0";

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

Future<void> main(List<String> args) async {
  // Verbose only in debug builds, where we want to "watch" a play
  // session unfold: cell taps, validation outcomes, hint requests,
  // playlist transitions. Release builds stick to INFO so the player
  // sees a single "puzzle loaded" line per puzzle in their console
  // and nothing else while they play.
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Parse CLI flags (documentation-generation mode). Non-flag positional
  // args are forwarded to [parseSharedPuzzleLine] so a v2_ line or a
  // share URL can still be passed as the first positional argument.
  bool noOnboarding = false;
  String? forcedLocale;
  String? scenarioPath;
  double? windowWidth;
  double? windowHeight;
  final positionalArgs = <String>[];
  for (final arg in args) {
    if (arg == '--no-onboarding') {
      noOnboarding = true;
    } else if (arg.startsWith('--lang=')) {
      forcedLocale = arg.substring('--lang='.length);
    } else if (arg.startsWith('--scenario=')) {
      scenarioPath = arg.substring('--scenario='.length);
    } else if (arg.startsWith('--width=')) {
      windowWidth = double.tryParse(arg.substring('--width='.length));
    } else if (arg.startsWith('--height=')) {
      windowHeight = double.tryParse(arg.substring('--height='.length));
    } else {
      positionalArgs.add(arg);
    }
  }

  // Apply window size on desktop before the first frame.
  if (windowWidth != null && windowHeight != null && !kIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setSize(Size(windowWidth, windowHeight));
    await windowManager.center();
  }

  final shared = parseSharedPuzzleLine(
    positionalArgs,
    webUri: kIsWeb ? Uri.base : null,
  );
  runApp(
    MyApp(
      initialSharedLine: shared,
      noOnboarding: noOnboarding,
      forcedLocale: forcedLocale,
      scenarioPath: scenarioPath,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.initialSharedLine,
    this.noOnboarding = false,
    this.forcedLocale,
    this.scenarioPath,
  });

  /// Puzzle line extracted from the launch URL or CLI args, if any.
  final String? initialSharedLine;

  /// When true, all onboarding dialogs and puzzle filtering are suppressed.
  final bool noOnboarding;

  /// When non-null, forces the app locale to the given language code
  /// and skips the initial language-chooser dialog.
  final String? forcedLocale;

  /// Path to an autopilot scenario file. When set, the app enters autopilot
  /// mode and drives the UI from the scenario actions.
  final String? scenarioPath;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale selectedLocale = Locale("en");
  ThemeModeType _themeMode = ThemeModeType.system;

  void setAppLocale(String newLocale) {
    setState(() {
      selectedLocale = Locale(newLocale);
    });
  }

  void setAppTheme(ThemeModeType newThemeMode) {
    setState(() {
      _themeMode = newThemeMode;
    });
  }

  @override
  void initState() {
    super.initState();
    selectedLocale = Locale(widget.forcedLocale ?? 'en');
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString("settingsThemeMode") ?? "system";
    final mode = ThemeModeType.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => ThemeModeType.system,
    );
    if (mounted) setState(() => _themeMode = mode);
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Get Some Puzzle',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: selectedLocale, // controlled by state
      // `beige` is a manual-only light theme, so `theme` switches to it
      // only when explicitly selected; `ThemeMode.system` keeps toggling
      // between light and dark.
      theme: _themeMode == ThemeModeType.beige ? beigeTheme : lightTheme,
      darkTheme: darkTheme,
      themeMode: resolveThemeMode(_themeMode),
      home: MyHomePage(
        title: 'Get Some Puzzle',
        setAppLocale: setAppLocale,
        setAppTheme: setAppTheme,
        initialSharedLine: widget.initialSharedLine,
        noOnboarding: widget.noOnboarding,
        forcedLocale: widget.forcedLocale,
        scenarioPath: widget.scenarioPath,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.setAppLocale,
    required this.setAppTheme,
    this.initialSharedLine,
    this.noOnboarding = false,
    this.forcedLocale,
    this.scenarioPath,
  });

  final String title;
  final ValueChanged<String> setAppLocale;
  final ValueChanged<ThemeModeType> setAppTheme;

  /// Puzzle line forwarded from main(args)/Uri.base. Consumed once on first
  /// database init; subsequent loads fall back to the playlist.
  final String? initialSharedLine;

  /// When true, onboarding dialogs, soft filtering, and all welcome/new-
  /// constraint modals are suppressed. Used for automated documentation
  /// screenshot generation.
  final bool noOnboarding;

  /// When non-null, the locale chooser dialog is skipped entirely and the
  /// app starts in this locale immediately. The selected locale is also
  /// persisted to SharedPreferences so subsequent manual launches remember
  /// the choice.
  final String? forcedLocale;

  /// Path to an autopilot scenario file. When set, the app enters autopilot
  /// mode and drives the UI from the scenario actions.
  final String? scenarioPath;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final GameModel game = GameModel();
  String locale = "en";
  Database? database;
  Settings settings = Settings();
  final ConstraintProgress progress = ConstraintProgress();
  bool initialized = false;
  bool shouldChooseLocale = true;
  // Set when a settings change (player level / auto-level) invalidates the
  // playlist while the Settings page is open. The costly recompute +
  // puzzle reload is deferred until the menu closes (see `onSettings`),
  // so it runs once instead of on every slider tick — and the new-rule
  // modal never fires on top of the Settings route.
  bool _playlistDirty = false;
  bool _testingFromEditor = false;
  // True when taps on free cells should prune one option from the
  // current option set instead of painting the cell. Only togglable on
  // 3+ colour puzzles: on a 2-colour domain the cycle collapses to a
  // setValue and the button stays hidden.
  bool _removeOptionMode = false;
  // True while the restart confirmation overlay is shown (topbar restart was
  // tapped). It pauses the game and turns the pause overlay into a two-button
  // confirm screen, guarding against accidental restarts (issue 21).
  bool _confirmingRestart = false;
  // Lets the keyboard shortcut handler open/close the navigation drawer
  // (ESC = Menu) without a separate Scaffold.of(context) lookup.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final log = Logger("HomePage");

  // ---------------------------------------------------------------------------
  // Autopilot mode
  // ---------------------------------------------------------------------------

  /// GlobalKey on the hint button so autopilot can query its position.
  final GlobalKey _hintButtonKey = GlobalKey();

  /// Reference to the current [PuzzleWidgetState], used for constraint
  /// position lookups and cell position lookups via [onStateReady] callback.
  PuzzleWidgetState? _puzzleWidgetState;

  /// True when autopilot mode is active (a scenario path was provided).
  bool get _autopilotMode => widget.scenarioPath != null;

  /// Parsed actions from the scenario file.
  List<AutopilotAction>? _autopilotActions;

  /// Index of the next action to execute.
  int _autopilotActionIndex = 0;

  /// Whether the autopilot engine is currently processing actions. Prevents
  /// re-entrance while waiting for a post-frame callback.
  bool _autopilotBusy = false;

  /// The autopilot driver (isolate or web fallback).
  AutopilotDriver? _autopilotDriver;

  /// Cursor overlay entry. Created lazily on first mouse/mouseTo action.
  OverlayEntry? _cursorOverlay;

  /// Position at which the cursor is currently drawn on screen.
  Offset _cursorDisplayedPos = Offset.zero;

  /// Monotonically increasing counter incremented every time a cursor
  /// animation starts. When it changes mid‑flight the old loop exits
  /// immediately so a newer move can take over.
  int _cursorAnimationGeneration = 0;

  // -------------------------------------------------------------------------
  // Dialog / subtitle overlay
  // -------------------------------------------------------------------------

  /// Subtitle overlay entry. Shown by `dialog "title" "text"`, removed by
  /// `dialog` (no args).
  OverlayEntry? _dialogOverlay;

  static const Color _defaultDialogTextColor = Color(0xFF90EE90);
  static const Color _defaultDialogFillColor = Colors.transparent;
  static const Color _defaultDialogBorderColor = Colors.black;

  Color _dialogTextColor = _defaultDialogTextColor;
  Color _dialogFillColor = _defaultDialogFillColor;
  Color _dialogBorderColor = _defaultDialogBorderColor;

  /// Full-screen background colour behind the dialog text. Drawn as a
  /// rectangle covering the entire screen, below the subtitle text. Set by
  /// the `background` action; transparent by default.
  Color _dialogBackgroundColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    game.addListener(() {
      // Trigger a rebuild so the build method picks up latest game state.
      if (mounted) setState(() {});
      _syncWakelock();
    });
    _syncWakelock();
    initialize();
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      WakelockPlus.disable();
    }
    _removeDialogOverlay();
    _removeCursorOverlay();
    _autopilotDriver?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    game.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In autopilot mode the scenario must keep running even when the
    // window loses focus — skip the auto-pause entirely.
    if (_autopilotMode) return;
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
    await settings.load();

    if (_autopilotMode) {
      log.info('AUTOPILOT MODE — scenario="${widget.scenarioPath}"');
      // Force the locale so no chooser appears.
      toggleLocale(widget.forcedLocale ?? 'en');
      // Disable the idle auto-pause — the scenario keeps running even
      // while the user (or the system) is not interacting with the window.
      game.idleTimeoutDuration = null;
      game.hintType = settings.hintType;
      game.learnedHintSlugs = const {};
      initialized = true;
      // Schedule the scenario engine on the next frame so the widget tree
      // is fully laid out before any action fires.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startAutopilot();
      });
      return;
    }

    await progress.load();

    // Apply forced locale before the database / locale futures so the
    // language chooser never appears and toggleLocale is not called
    // twice for the same code path.
    if (widget.forcedLocale != null) {
      toggleLocale(widget.forcedLocale!);
    }

    // When onboarding is disabled, pre-populate every slug as "already
    // seen" so the new-constraint / welcome modals never fire during
    // the very first puzzle load (which calls openPuzzle →
    // _surfaceNewConstraintsIfAny inside initializeDatabase).
    if (widget.noOnboarding) {
      final now = DateTime.now();
      for (final slug in OnboardingPhase.allKnownSlugs) {
        progress.noteSeen(slug, now);
      }
      await progress.save();
    }

    game.idleTimeoutDuration = settings.idleTimeoutDuration;
    game.hintType = settings.hintType;
    game.learnedHintSlugs = progress.firstSeen.keys.toSet();
    var futures = <Future>[];
    futures.add(initializeDatabase(settings.playerLevel));
    futures.add(initializeLocale());
    await Future.wait(futures);

    // Post-database: exit onboarding on the Database side too (reset
    // phase counters + rebuild the playlist without any onboarding
    // filtering) so subsequent puzzles are drawn from the full catalog.
    if (widget.noOnboarding && database != null) {
      await database!.skipOnboarding();
      database!.preparePlaylist();
    }

    // Refresh the auto-level from the freshly loaded global play history.
    // Without this, a returning player's level would only update at the end
    // of the first drained batch — so it could stay stale (e.g. 0) across
    // many sessions if they never complete a batch. The level is computed
    // over the full history across every collection, so a player who
    // spread their plays over several collections still gets a value.
    if (settings.autoLevel && database != null) {
      final newLevel = database!.computePlayerLevel(
        fallback: settings.playerLevel,
      );
      if (newLevel != settings.playerLevel) {
        settings.playerLevel = newLevel;
        await settings.save();
        database!.setPlayerLevel(newLevel);
      }
    }

    // The database's stats load may have backfilled `progress` from
    // legacy plays — persist whatever new entries that produced so a
    // returning player doesn't have to re-derive them on every launch.
    await progress.save();
    initialized = true;
    // Validate statsDirectory and auto-clear if the path is
    // inaccessible (e.g. an old filesystem path saved before the
    // SAF-migration commit on Android 11+).
    final dir = settings.statsDirectory;
    if (database != null && dir != null && !kIsWeb) {
      await _validateAndAutoClearStatsDir(database!, dir);
    }
  }

  Future<void> _validateAndAutoClearStatsDir(Database db, String dir) async {
    final valid = await db.validateStatsDirectory();
    if (valid) return;
    await db.clearStatsDirectory();
    await settings.setStatsDirectory(null);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.statsSyncDirectoryAutoCleared,
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Autopilot engine
  // ---------------------------------------------------------------------------

  /// Wait for the next frame boundary so the widget tree is fully laid out
  /// after a state mutation.
  Future<void> _autopilotWaitFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    return completer.future;
  }

  /// Start the autopilot engine: read and parse the scenario file via the
  /// [AutopilotDriver], then execute the actions sequentially.
  Future<void> _startAutopilot() async {
    final path = widget.scenarioPath;
    if (path == null || path.isEmpty) return;

    final driver = AutopilotDriver();
    _autopilotDriver = driver;
    final actions = await driver.compute(path);
    if (actions.isEmpty) {
      log.info('autopilot: scenario "$path" produced no actions');
      return;
    }

    log.info('autopilot: loaded ${actions.length} actions from "$path"');
    _autopilotActions = actions;
    _autopilotActionIndex = 0;
    _processNextAutopilotAction();
  }

  /// Process the next pending action from the scenario, or stop when depleted.
  Future<void> _processNextAutopilotAction() async {
    if (_autopilotBusy) return;
    _autopilotBusy = true;

    while (_autopilotActionIndex < (_autopilotActions?.length ?? 0)) {
      final action = _autopilotActions![_autopilotActionIndex++];

      // Build a human-readable description of the action for the log line.
      final lineDesc = switch (action) {
        LoadStateAction(:final v2Line) =>
          'loadState ${v2Line.length > 40 ? "${v2Line.substring(0, 40)}…" : v2Line}',
        WaitAction(:final milliseconds) => 'wait $milliseconds ms',
        MouseAction(:final col, :final row) => 'mouse $col,$row',
        MouseToAction(:final target) => 'mouseTo $target',
        SetValueAction(:final col, :final row, :final value) =>
          'setValue $col,$row,${value.name}',
        DialogAction(:final title, :final text) =>
          title == null && text == null ? 'dialog (close)' : 'dialog',
        TextColorAction(
          :final textColor,
          :final fillColor,
          :final borderColor,
        ) =>
          'textcolor $textColor $fillColor $borderColor',
        BackgroundAction(:final color) => 'background $color',
        HintAction() => 'hint',
      };
      log.info('autopilot: START $lineDesc');

      switch (action) {
        case LoadStateAction(:final v2Line):
          await _performLoadState(v2Line);

        case WaitAction(:final milliseconds):
          await Future.delayed(Duration(milliseconds: milliseconds));

        case MouseAction(:final col, :final row):
          await _performMouse(col, row);

        case MouseToAction(:final target):
          await _performMouseTo(target);

        case SetValueAction(:final col, :final row, :final value):
          await _performSetValue(col, row, value);

        case DialogAction(:final title, :final text):
          await _performDialog(title, text);

        case TextColorAction():
          await _performTextColor(action);

        case BackgroundAction(:final color):
          await _performBackground(color);

        case HintAction():
          await _performHint();
      }

      log.info('autopilot: END $lineDesc');
    }

    _autopilotBusy = false;
    log.info('autopilot: scenario completed');
    // Brief pause so the viewer sees the final state, then close.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!kIsWeb) exit(0);
  }

  /// Ensure the cursor overlay is shown in the overlay.
  void _ensureCursorOverlay() {
    if (_cursorOverlay != null) return;
    _cursorOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: _cursorDisplayedPos.dx,
        top: _cursorDisplayedPos.dy,
        child: const FakeCursor(),
      ),
    );
    Overlay.of(context).insert(_cursorOverlay!);
  }

  /// Remove the cursor overlay if it exists.
  void _removeCursorOverlay() {
    _cursorOverlay?.remove();
    _cursorOverlay = null;
  }

  /// Remove the subtitle overlay if it exists.
  void _removeDialogOverlay() {
    _dialogOverlay?.remove();
    _dialogOverlay = null;
  }

  /// Animate the cursor from its current displayed position to [target].
  ///
  /// The base speed is 1 px/ms, with a floor of 200 ms (short moves feel
  /// deliberate) and a ceiling of 500 ms (long moves don't drag).
  /// Returns when the animation is complete so the caller can await it.
  Future<void> _updateCursorPosition(Offset target) async {
    const speedPxPerMs = 1.0;
    const minDurationMs = 200;
    const maxDurationMs = 500;

    final start = _cursorDisplayedPos;
    final distance = (target - start).distance;

    // Already at destination — show the position directly.
    if (distance < 1.0) {
      _cursorDisplayedPos = target;
      _ensureCursorOverlay();
      _cursorOverlay?.markNeedsBuild();
      return;
    }

    final durationMs = (distance / speedPxPerMs).round().clamp(
      minDurationMs,
      maxDurationMs,
    );
    final dt = Duration(milliseconds: durationMs);
    log.fine(
      'autopilot: cursor move distance=${distance.toStringAsFixed(0)}px '
      'duration=${durationMs}ms',
    );

    _ensureCursorOverlay();

    // Bump the generation so any stale animation loop exits immediately.
    final gen = ++_cursorAnimationGeneration;

    // Time-based linear interpolation: sample every ~16 ms (≈60 fps).
    final t0 = DateTime.now();
    while (true) {
      // A newer animation started — stop this one.
      if (_cursorAnimationGeneration != gen) return;
      final elapsed = DateTime.now().difference(t0);
      if (elapsed >= dt) break;
      final t = elapsed.inMicroseconds / dt.inMicroseconds;
      _cursorDisplayedPos = Offset.lerp(start, target, t)!;
      _cursorOverlay?.markNeedsBuild();
      // Yield control so the next frame can paint the updated position.
      await Future.delayed(const Duration(milliseconds: 16));
    }
    _cursorDisplayedPos = target;
    _cursorOverlay?.markNeedsBuild();
  }

  /// Load a puzzle from a v2 line.
  Future<void> _performLoadState(String v2Line) async {
    try {
      PuzzleData(v2Line); // validate syntax
      game.loadPuzzleFromLine(v2Line);
      // Wait for the framework to rebuild and lay out the PuzzleWidget
      // before the next action fires.
      await _autopilotWaitFrame();
    } catch (e) {
      log.warning('autopilot: loadState failed: $e');
    }
  }

  /// Move the cursor to the centre of grid cell (col, row).
  Future<void> _performMouse(int col, int row) async {
    // Wait for the widget tree to be laid out after any preceding action
    await _autopilotWaitFrame();

    final state = _puzzleWidgetState;
    if (state == null) {
      log.warning('autopilot: mouse($col,$row) — puzzle widget not ready');
      return;
    }

    final puzzle = game.currentPuzzle;
    if (puzzle == null) {
      log.warning('autopilot: mouse($col,$row) — no puzzle loaded');
      return;
    }
    if (col < 0 || col >= puzzle.width || row < 0 || row >= puzzle.height) {
      log.warning(
        'autopilot: mouse($col,$row) — out of bounds '
        '(${puzzle.width}x${puzzle.height})',
      );
      return;
    }

    final idx = row * puzzle.width + col;
    final pos = state.getCellGlobalCenter(idx);
    if (pos == null) {
      log.warning('autopilot: mouse($col,$row) — grid not laid out yet');
      return;
    }
    await _updateCursorPosition(pos);
  }

  /// Move the cursor to a named widget target.
  Future<void> _performMouseTo(String target) async {
    await _autopilotWaitFrame();

    if (target == 'hint') {
      final box =
          _hintButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        log.warning('autopilot: mouseTo hint — button not laid out yet');
        return;
      }
      await _updateCursorPosition(
        box.localToGlobal(box.size.center(Offset.zero)),
      );
      return;
    }

    // Constraint reference: resolve via PuzzleWidgetState
    final state = _puzzleWidgetState;
    if (state == null) {
      log.warning('autopilot: mouseTo $target — puzzle widget not ready');
      return;
    }
    final pos = state.getConstraintGlobalPosition(target);
    if (pos == null) {
      log.warning(
        'autopilot: mouseTo $target — constraint not found or not laid out',
      );
      return;
    }
    await _updateCursorPosition(pos);
  }

  /// Set a cell to an exact colour, then wait for the next frame so the UI
  /// redraws before the next action fires.
  Future<void> _performSetValue(int col, int row, CellValue value) async {
    final puzzle = game.currentPuzzle;
    if (puzzle == null) {
      log.warning('autopilot: setValue($col,$row,$value) — no puzzle loaded');
      return;
    }
    if (col < 0 || col >= puzzle.width || row < 0 || row >= puzzle.height) {
      log.warning(
        'autopilot: setValue($col,$row,$value) — out of bounds '
        '(${puzzle.width}x${puzzle.height})',
      );
      return;
    }
    final idx = row * puzzle.width + col;
    if (puzzle.cells[idx].readonly) {
      log.warning('autopilot: setValue($col,$row,$value) — cell is readonly');
      return;
    }
    puzzle.setValue(idx, value, ignoreOptions: true);
    puzzle.updateConstraintStatus();
    game.refresh();
    // Wait for the widget tree to rebuild and display the new cell colour.
    await _autopilotWaitFrame();
  }

  /// One tap on the hint button (mirrors the existing hint flow).
  Future<void> _performHint() async {
    if (game.currentPuzzle == null) return;
    // Schedule the hint on the next frame so any pending setState from
    // the previous action has committed, then wait for the hint's own
    // rebuild to complete before the next action runs.
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        done.complete();
        return;
      }
      showHelpMove();
      // Wait one more frame so the hint's visual changes (highlights,
      // applied move, stage text) are painted.
      WidgetsBinding.instance.addPostFrameCallback((_) => done.complete());
    });
    await done.future;
  }

  /// Show or close the subtitle overlay.
  Future<void> _performDialog(String? title, String? text) async {
    // Both null → close any open subtitle.
    if (title == null && text == null) {
      _removeDialogOverlay();
      return;
    }
    // Show subtitle overlay (movie-subtitle style, centered), optionally on
    // top of a full-screen background rectangle set by `background`.
    _removeDialogOverlay();
    _dialogOverlay = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Stack(
          children: [
            // Full-screen background rectangle, below the dialog text.
            if (_dialogBackgroundColor != Colors.transparent)
              Positioned.fill(child: ColoredBox(color: _dialogBackgroundColor)),
            // Centered dialog text on top of the background.
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AutopilotDialog(
                  title: title,
                  text: text ?? '',
                  textColor: _dialogTextColor,
                  fillColor: _dialogFillColor,
                  borderColor: _dialogBorderColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_dialogOverlay!);
    await _autopilotWaitFrame();
  }

  /// Resolve a raw colour token from the scenario to a [Color].
  ///
  /// Resolution order:
  ///   1. `default` → returns `null` (caller resets the slot)
  ///   2. [PuzzleColors.resolveByName] → theme semantic colour
  ///   3. `#RRGGBB` / `#AARRGGBB` hex code
  ///   4. Otherwise → logged warning, returns `null`
  Color? _resolveColorToken(String token) {
    if (token.toLowerCase() == 'default') return null;

    // Theme semantic colours.
    final pc = Theme.of(context).extension<PuzzleColors>();
    if (pc != null) {
      final c = pc.resolveByName(token);
      if (c != null) return c;
    }

    // Hex: #RRGGBB or #AARRGGBB
    if (token.startsWith('#') && token.length > 1) {
      final hex = token.substring(1);
      if (hex.length == 6) {
        final v = int.tryParse(hex, radix: 16);
        if (v != null) return Color(0xFF000000 | v);
      } else if (hex.length == 8) {
        final v = int.tryParse(hex, radix: 16);
        if (v != null) return Color(v);
      }
    }

    log.warning('autopilot: unrecognized text colour token "$token"');
    return null; // leave unchanged
  }

  /// Apply a [TextColorAction] from the scenario.
  Future<void> _performTextColor(TextColorAction action) async {
    final tc = _resolveColorToken(action.textColor);
    final fc = _resolveColorToken(action.fillColor);
    final bc = _resolveColorToken(action.borderColor);

    _dialogTextColor = tc ?? _defaultDialogTextColor;
    _dialogFillColor = fc ?? _defaultDialogFillColor;
    _dialogBorderColor = bc ?? _defaultDialogBorderColor;
  }

  /// Apply a [BackgroundAction] from the scenario.
  ///
  /// Resolves the colour token and stores it; the rectangle is drawn on the
  /// next [DialogAction]'s overlay, below the dialog text.
  Future<void> _performBackground(String token) async {
    final c = _resolveColorToken(token);
    _dialogBackgroundColor = c ?? Colors.transparent;
  }

  Future<void> initializeDatabase(int playerLevel) async {
    final db = Database(playerLevel: playerLevel, progress: progress);
    db.statsDirectory = settings.statsDirectory;
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
    // The new-constraint modal was deferred while the locale chooser
    // was up. Re-trigger it now for the puzzle that's already loaded
    // behind the chooser, if any.
    final puz = game.currentMeta;
    if (puz != null) _surfaceNewConstraintsIfAny(puz);
  }

  // ---------------------------------------------------------------------------
  // Puzzle lifecycle (thin wrappers around GameModel)
  // ---------------------------------------------------------------------------

  /// Emit a debug-only summary of the onboarding state — current
  /// strict phase (or `soft` / `done` once past P3), completions
  /// counter, and the slug sets the player has and hasn't met. Pairs
  /// with the per-puzzle info log so a debug session can reconstruct
  /// the player's journey from the logs alone.
  void _logOnboardingState() {
    if (database == null) return;
    final db = database!;
    final seen = progress.firstSeen.keys.toList()..sort();
    final unseen =
        OnboardingPhase.allKnownSlugs
            .where((s) => !progress.firstSeen.containsKey(s))
            .toList()
          ..sort();
    final phaseName = db.currentPhase != null
        ? 'P${db.currentPhase!.index} (intro=${db.currentPhase!.introducing})'
        : (db.isInOnboarding ? 'soft' : 'done');
    log.fine(
      'Onboarding: phase=$phaseName '
      'completions=${db.onboardingCompletions} '
      'seen=$seen unseen=$unseen',
    );
  }

  void loadPuzzle({bool skipped = false}) {
    if (database == null) return;
    if (game.currentMeta != null && skipped) {
      game.currentMeta!.skipped = DateTime.now();
    }
    final nextPuzzle = database!.next();
    if (nextPuzzle != null) {
      // The single info-level log emitted per puzzle: short summary
      // plus the canonical key so the puzzle can be looked up in
      // stats.txt or in the asset files. The canonical key drops the
      // version prefix, the cached solution and the cplx tail — the
      // remaining domain/dims/prefill/sorted-constraints is what
      // identifies the puzzle across format evolutions.
      log.info(
        'Puzzle loaded: ${nextPuzzle.width}x${nextPuzzle.height} '
        'cplx=${nextPuzzle.cplx} '
        'rules=${nextPuzzle.rules.toSet().toList()..sort()} '
        'key=${canonicalPuzzleKey(nextPuzzle.lineRepresentation)}',
      );
      _logOnboardingState();
      openPuzzle(nextPuzzle);
    } else {
      game.clearPuzzle();
    }
  }

  void openPuzzle(PuzzleData puz) {
    // Pass the current screen orientation so `GameModel.openPuzzle` can
    // apply the auto-rotation BEFORE the first build, avoiding a one-frame
    // flicker where the puzzle would otherwise appear in the wrong
    // orientation then snap into place. Orientation changes during play
    // are still handled by the post-frame callback in build().
    final size = MediaQuery.sizeOf(context);
    game.openPuzzle(
      puz,
      database!.playlist.length,
      progressRestoredText: AppLocalizations.of(context)!.progressRestored,
      screenIsLandscape: size.width > size.height,
    );
    // The `addConstraint` hint search is deferred to the first hint tap
    // (`GameModel.onHintTap`), not run eagerly on open — it is expensive and,
    // on web, runs on the main thread.
    _applyGrayoutSetting();
    _surfaceNewConstraintsIfAny(puz);
  }

  void _applyGrayoutSetting() {
    final p = game.currentPuzzle;
    if (p == null) return;
    p.grayoutEnabled = settings.grayoutEnabled;
    p.updateConstraintStatus();
    game.refresh();
  }

  /// Reload stats from storage and recompute auto-level if enabled.
  /// Marks the playlist dirty so it is rebuilt when the settings page
  /// closes, following the same deferred-rebuild pattern used for
  /// manual level changes (see `onSettingsChange` → `_playlistDirty`).
  Future<void> _reloadStatsAndLevel() async {
    if (database == null) return;
    await database!.reloadStatsFromStorage();
    if (settings.autoLevel) {
      final newLevel = database!.computePlayerLevel(
        fallback: settings.playerLevel,
      );
      if (newLevel != settings.playerLevel) {
        settings.playerLevel = newLevel;
        await settings.save();
      }
    }
    database!.setPlayerLevel(settings.playerLevel);
    _playlistDirty = true;
    game.refresh();
  }

  /// If the puzzle declares constraint slugs the player has never
  /// seen before, surface a single explanation modal listing all the
  /// new ones. We schedule a post-frame callback so the modal opens
  /// on top of the already-mounted puzzle widget — opening it during
  /// the same frame that calls `setState` from the playlist transition
  /// tends to break the animation pipeline.
  ///
  /// While the locale chooser is up the modal would obscure it, so we
  /// defer the trigger until [toggleLocale] has resolved (the puzzle
  /// is still loaded behind the chooser so the modal will fire as
  /// soon as the player picks a language).
  void _surfaceNewConstraintsIfAny(PuzzleData puz) {
    // When onboarding is globally suppressed (--no-onboarding CLI flag)
    // skip every modal including the welcome, new-rule, third-colour-
    // suggestion and onboarding-complete dialogs.
    if (widget.noOnboarding || _autopilotMode) return;

    // A single puzzle line typically declares the same slug several
    // times (e.g. two FM: rules with different params). Build a Set
    // so each slug fires its modal section exactly once.
    final newSlugs = <String>{
      for (final slug in puz.rules)
        if (slug.isNotEmpty && slug != 'TX' && progress.isFirstTimeFor(slug))
          slug,
    };
    if (newSlugs.isEmpty) {
      // No new rule to surface — but the 3-colour suggestion has its
      // own independent trigger, so we still give it a chance to fire.
      _maybeSuggestThirdColor();
      return;
    }
    if (_modalInFlight) return;
    _modalInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || shouldChooseLocale) {
        _modalInFlight = false;
        return;
      }
      // First-ever rule encounter → show the game-intro screen before
      // the per-rule modal. `firstSeen.isEmpty` is the cleanest signal:
      // true on a fresh install AND after "Rejouer l'onboarding"
      // (which clears firstSeen post-loadStats).
      bool skipped = false;
      if (progress.firstSeen.isEmpty) {
        skipped = await WelcomeDialog.show(context);
        if (!mounted) {
          _modalInFlight = false;
          return;
        }
      }
      if (!skipped) {
        // Collapse merged pairs (CC↔RC, RT↔CT, JC↔JR) so the dialog
        // renders each concept only once — they share the same
        // explanation body and the row/column distinction is secondary.
        final dialogSlugs = <String>{};
        for (final slug in newSlugs) {
          var display = slug;
          for (final entry in mergedRuleGroups.entries) {
            if (entry.value.contains(slug)) {
              display = entry.key;
              break;
            }
          }
          dialogSlugs.add(display);
        }
        skipped = await NewConstraintDialog.show(
          context,
          dialogSlugs,
          showSkipButton: true,
        );
      }
      final now = DateTime.now();
      // Snapshot before noting slugs / skipping so we can detect the
      // moment the player crosses out of onboarding below.
      final wasInOnboarding = database?.isInOnboarding ?? false;
      if (skipped) {
        // Mark every known slug as seen so the modal never fires
        // again, then push the phase counter past every strict phase
        // so the playlist sampler exits onboarding mode immediately.
        // Together they also defuse [Database._softFilterActive].
        for (final slug in OnboardingPhase.allKnownSlugs) {
          progress.noteSeen(slug, now);
        }
        if (database != null) {
          await database!.skipOnboarding();
          database!.preparePlaylist();
        }
      } else {
        for (final slug in newSlugs) {
          progress.noteSeen(slug, now);
          // Merged families (CC↔RC, RT↔CT, JC↔JR) share the same
          // onboarding explanation. Mark every sibling as seen too so
          // the soft filter doesn't re-introduce it later as a separate
          // discovery.
          for (final entry in mergedRuleGroups.entries) {
            if (entry.value.contains(slug)) {
              for (final sibling in entry.value) {
                progress.noteSeen(sibling, now);
              }
              break;
            }
          }
        }
      }
      // Persist whatever new slugs were dismissed; failing silently
      // here only means the player will see the modal again next
      // launch (no game-state corruption).
      await progress.save();
      // Just left onboarding (skipped, or noted the final unseen slug):
      // the open-page rule filters still carry the last onboarding
      // recommendation. Reset them to default so the player isn't stuck
      // wanting/banning the closing onboarding slug.
      if (wasInOnboarding && database != null && !database!.isInOnboarding) {
        await database!.resetRuleFilters();
      }
      // The last unseen slug just got marked as seen. If the player is
      // no longer in onboarding (both strict phases and soft filter
      // satisfied), congratulate them once.
      if (!skipped &&
          database != null &&
          !database!.isInOnboarding &&
          mounted) {
        await OnboardingCompleteDialog.show(context);
      }
      _modalInFlight = false;
      if (skipped && mounted) setState(() {});
      // Chain the 3-colour suggestion check once the new-rule flow is
      // fully resolved. It self-guards on `shouldSuggestThirdColor` so
      // the common case (modal already shown, or threshold not met)
      // returns immediately without any UI side effect.
      _maybeSuggestThirdColor();
    });
  }

  /// Show the 3-colour suggestion modal if all four gating conditions
  /// hold (cf. [Database.shouldSuggestThirdColor]). The modal is
  /// scheduled on the next frame so it stacks cleanly on top of any
  /// modal that just finished, and the result is acted on: tapping
  /// "Try it" removes the `d3` ban from the player's domain filter
  /// and rebuilds the playlist immediately, so the next puzzle draws
  /// from the wider pool. Either way the suggestion is marked as
  /// shown so it never fires again.
  Future<void> _maybeSuggestThirdColor() async {
    if (!mounted || database == null || _autopilotMode) {
      log.fine(
        '_maybeSuggestThirdColor: skipped (mounted=$mounted, '
        'db=${database != null})',
      );
      return;
    }
    if (_modalInFlight) {
      log.fine('_maybeSuggestThirdColor: skipped (modalInFlight)');
      return;
    }
    if (!database!.shouldSuggestThirdColor()) return;
    log.info('_maybeSuggestThirdColor: showing modal');
    _modalInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _modalInFlight = false;
        return;
      }
      final wantsIt = await ThirdColorSuggestionDialog.show(context);
      await database!.noteThirdColorSuggestionShown();
      _modalInFlight = false;
      if (wantsIt && mounted) {
        // Opt-in path: swap the domain ban so the next playlist
        // surfaces 3-colour puzzles exclusively. Just removing d3
        // would mix 2- and 3-colour puzzles and the player would
        // routinely land back on a black-and-white grid — defeating
        // the point of "Try it". Forcing d3 only is also discoverable
        // from the Open page filters, where the player can flip back
        // to mixed (or 2-only) any time.
        final filters = database!.currentFilters;
        final newBanned = Set<String>.from(filters.bannedDomains)
          ..remove('d3')
          ..add('d2');
        filters.bannedDomains = newBanned;
        await filters.save();
        database!.preparePlaylist();
        // Drop the in-progress 2-colour puzzle and pull a fresh one
        // from the just-rebuilt playlist — otherwise the player keeps
        // staring at the same black-and-white grid after asking to
        // try 3 colours. We don't pass `skipped: true`: the player
        // didn't reject the puzzle, the app moved them on. Recording
        // it as skipped would pollute the stats.
        loadPuzzle();
      }
    });
  }

  /// True while a new-constraint modal is queued or open. Prevents
  /// stacking duplicate modals if `openPuzzle` is called twice for the
  /// same puzzle, or if the post-frame callback re-enters via the
  /// locale-chooser fallback.
  bool _modalInFlight = false;

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
    if (game.handleTap(idx, removeOptionMode: _removeOptionMode)) {
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

  void handlePuzzleLongPress(int idx) {
    if (game.handleLongPress(idx, removeOptionMode: _removeOptionMode)) {
      _handleCheck();
    }
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
    // Bump the global usable-plays counter so the recommendation gate
    // clears as the session progresses — without this the gate only
    // sees the stats loaded at app start and stays stuck below the
    // threshold across an entire session for a fresh player.
    final completedMeta = game.currentMeta;
    if (completedMeta != null) {
      database?.notePuzzleCompleted(completedMeta);
    }
    // Auto-level recompute is deferred to the end of the batch (when
    // the playlist becomes empty). Recomputing after every puzzle would
    // shift `playerLevel` continuously, which then re-runs
    // `preparePlaylist` and produces a fresh batch of 20 — meaning the
    // player would never reach the EndOfPlaylist screen and never see
    // the cross-collection suggestion. Holding the level steady for one
    // batch also makes the "Lv N" display feel less jittery.
    //
    // The recompute fires exactly when the player has just finished the
    // last puzzle of the batch (playlist empty post-`next()`), so the
    // freshly-shown EndOfPlaylist reads an up-to-date `playerLevel` and
    // a correct `recommendedCollectionKey`. We deliberately do not call
    // `preparePlaylist` here — the user's explicit Continue/Switch
    // action will rebuild the batch.
    if (settings.autoLevel && database != null && database!.playlist.isEmpty) {
      final newLevel = database!.computePlayerLevel(
        fallback: settings.playerLevel,
      );
      if (newLevel != settings.playerLevel) {
        settings.playerLevel = newLevel;
        database!.setPlayerLevel(newLevel);
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
      // Resuming also cancels a pending restart confirmation.
      _confirmingRestart = false;
      game.resume();
      if (game.currentPuzzle == null) {
        loadPuzzle();
      }
    } else {
      game.pause();
    }
  }

  /// Confirms the restart requested from the topbar: reset the grid and resume
  /// on the fresh puzzle.
  void _confirmRestart() {
    setState(() {
      _confirmingRestart = false;
      game.restart();
      game.resume();
    });
  }

  void _onDrawerChanged(bool isOpened) {
    if (isOpened && game.currentPuzzle != null && !game.betweenPuzzles) {
      game.pause();
    }
  }

  /// Synchronise le wakelock avec l'état du jeu.
  /// Actif uniquement quand un puzzle est en cours, non pausé,
  /// et qu'on n'est pas entre deux puzzles.
  void _syncWakelock() {
    if (kIsWeb) return;
    final active =
        game.currentPuzzle != null && !game.paused && !game.betweenPuzzles;
    if (active) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
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
    if (givenBy is Constraint) return constraintNameForSlug(l10n, givenBy.slug);
    assert(false, 'Unexpected hint source ${givenBy.runtimeType}');
    return givenBy.serialize();
  }

  HintTexts _buildHintTexts() {
    final l10n = AppLocalizations.of(context)!;
    return HintTexts(
      hintConstraintsInvalid: (count) => l10n.hintConstraintsInvalid(count),
      hintCellWrong: l10n.hintCellWrong,
      hintAllCorrectSoFar: l10n.hintAllCorrectSoFar,
      hintCellDeducible: l10n.hintCellDeducible,
      hintImpossible: l10n.hintImpossible,
      hintForce: l10n.hintForce,
      hintDeducedFrom: (c) {
        if (c is Complicity) {
          final (s1, s2) = c.slugs;
          if (s1 == s2) {
            return l10n.hintComplicityTwin(constraintNameForSlug(l10n, s1));
          }
          return l10n.hintComplicity(
            constraintNameForSlug(l10n, s1),
            constraintNameForSlug(l10n, s2),
          );
        }
        return l10n.hintDeducedFrom(_constraintName(c));
      },
      hintConstraintAdded: l10n.hintConstraintAdded,
      hintConstraintInprogress: l10n.hintConstraintInprogress,
      hintConstraintNone: l10n.hintConstraintNone,
      hintCellOptionRemovable: l10n.hintCellOptionRemovable,
      hintForceRemoveOption: l10n.hintForceRemoveOption,
      hintRemoveOptionDeducedFrom: (c) {
        // Mirrors the dispatch used for the setValue-side
        // `hintDeducedFrom` callback above: complicities pick the
        // twin/distinct phrasing, regular constraints use the single-
        // slot wording. Phrasings are parallel to `hintComplicity` /
        // `hintComplicityTwin` but anchored on "an option can be ruled
        // out" rather than "this cell can be deduced".
        if (c is Complicity) {
          final (s1, s2) = c.slugs;
          if (s1 == s2) {
            return l10n.hintRemoveOptionComplicityTwin(
              constraintNameForSlug(l10n, s1),
            );
          }
          return l10n.hintRemoveOptionComplicity(
            constraintNameForSlug(l10n, s1),
            constraintNameForSlug(l10n, s2),
          );
        }
        return l10n.hintRemoveOptionDeducedFrom(_constraintName(c));
      },
    );
  }

  void showHelpMove() {
    game.onHintTap(
      settings,
      _buildHintTexts(),
      onPuzzleCompleted: _onPuzzleCompleted,
    );
  }

  /// Top-bar help button: open a reminder of the constraints used by
  /// the current puzzle. Row/column pairs (RC/CC, JR/JC, RT/CT) are
  /// collapsed to their display slug so the modal lists each concept
  /// once, matching the onboarding ("New rule!") modal.
  void _showConstraintsHelp() {
    final p = game.currentPuzzle;
    if (p == null) return;
    final slugs = collapseMergedRules(
      p.constraints.map((c) => c.slug).where((s) => s.isNotEmpty),
    );
    if (slugs.isEmpty) return;
    ConstraintHelpDialog.show(context, slugs);
  }

  void _onHintTypeChanged() {
    if (game.currentPuzzle == null) return;
    // Force a clean cycle: a stage from the previous mode would be confusing
    // (e.g. "stage 2 = cell shown" doesn't exist in addConstraint).
    game.resetHintCycle();
    // Keep GameModel's mirror in sync before kicking the worker — the gate
    // inside `startHintConstraintComputation` reads it to decide whether
    // to actually run. Refresh the learned slugs too, so the worker never
    // offers a constraint type the player has not yet learned.
    game.hintType = settings.hintType;
    game.learnedHintSlugs = progress.firstSeen.keys.toSet();
    // Switching to addConstraint no longer pre-computes here — the search
    // runs on demand at the first hint tap. Switching away cancels any
    // in-flight pass.
    if (settings.hintType != HintType.addConstraint) {
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
    loadPuzzle();
  }

  // ---------------------------------------------------------------------------
  // Keyboard shortcuts (desktop)
  // ---------------------------------------------------------------------------

  /// Manual completion check, shared by the topbar Validate button and the
  /// Enter shortcut. No-op unless the grid is complete and the rating screen
  /// isn't showing.
  void _manualValidate() {
    final puzzle = game.currentPuzzle;
    if (puzzle == null || !puzzle.complete || game.betweenPuzzles) return;
    final l10n = AppLocalizations.of(context)!;
    game.checkPuzzle(
      settings,
      manualCheck: true,
      invalidConstraintsText: l10n.someConstraintsInvalid,
      errorsCountText: l10n.errorsCount,
      onPuzzleCompleted: _onPuzzleCompleted,
    );
  }

  /// Routes hardware-keyboard shortcuts during play. Returns
  /// [KeyEventResult.handled] when a shortcut fires so the event stops
  /// bubbling. Only key-down events act. Dialogs and the drawer take focus
  /// from this node while open, so they naturally suppress these shortcuts
  /// (ESC closes the drawer again). Each branch mirrors the matching topbar
  /// button's enable condition.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!initialized || shouldChooseLocale) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Menu (ESC) and pause (P) stay available even while paused.
    if (key == LogicalKeyboardKey.escape) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold == null) return KeyEventResult.ignored;
      if (scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
      } else {
        scaffold.openDrawer();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      if (database == null) return KeyEventResult.ignored;
      togglePause();
      return KeyEventResult.handled;
    }

    // The remaining shortcuts only make sense while actively playing.
    final playing =
        game.currentPuzzle != null && !game.paused && !game.betweenPuzzles;
    if (!playing) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.keyU) {
      if (game.history.isEmpty) return KeyEventResult.ignored;
      game.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      if (game.history.isEmpty) return KeyEventResult.ignored;
      // Mirror the topbar restart: pause + confirmation overlay (issue 21).
      setState(() {
        _confirmingRestart = true;
        game.pause();
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH) {
      showHelpMove();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      loadPuzzle(skipped: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      // Toggle setValue / removeOption — only meaningful on 3+ colour
      // puzzles, where the topbar paint-bucket button is shown.
      if (game.currentPuzzle!.domain.length <= 2) {
        return KeyEventResult.ignored;
      }
      setState(() => _removeOptionMode = !_removeOptionMode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (settings.validateType != ValidateType.manual) {
        return KeyEventResult.ignored;
      }
      if (!game.currentPuzzle!.complete) return KeyEventResult.ignored;
      _manualValidate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

    // Auto-rotate the puzzle when its aspect ratio doesn't match the screen
    // orientation. Without this, a landscape puzzle on a portrait screen
    // gets cellSize squeezed by the narrow dimension and renders tiny cells
    // with huge empty bands. Rotation is logically transparent — same
    // solutions, same constraints (re-expressed) — so the player keeps the
    // same stats entry across orientations (canonicalPuzzleKey is rotation-
    // invariant).
    //
    // The *initial* rotation at puzzle-open time is applied synchronously
    // by `GameModel.openPuzzle(screenIsLandscape:)` so the first build
    // already sees the correct orientation. This post-frame branch only
    // catches device-orientation changes that happen *after* the puzzle is
    // displayed (and a safety net if the orientation hint wasn't passed).
    // Scheduled post-frame to avoid mutating state during build.
    // In autopilot mode the puzzle must stay in its original orientation
    // so that scenario coordinates remain valid — skip auto-rotation.
    if (_autopilotMode) {
      // no-op
    } else if (game.currentPuzzle != null) {
      final p = game.currentPuzzle!;
      if (p.width != p.height) {
        final screenW = MediaQuery.sizeOf(context).width;
        final screenH = MediaQuery.sizeOf(context).height;
        final puzzleLandscape = p.width > p.height;
        final screenLandscape = screenW > screenH;
        if (puzzleLandscape != screenLandscape) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Re-check the predicate at frame time: another build/rotation
            // may have already settled the orientation. `identical` ensures
            // we don't re-rotate the rotation we just produced.
            if (!identical(game.currentPuzzle, p)) return;
            game.cancelHintConstraintComputation();
            game.availableHintConstraints = [];
            game.rotateCurrentPuzzle();
            // Rotation invalidates prior candidates (cell indices shift); the
            // next hint tap recomputes from the rotated state.
          });
        }
      }
    }

    double cellSize = 32.0;
    if (game.currentPuzzle != null) {
      final hasLeftBar = game.currentPuzzle!.constraints.any(
        (c) =>
            c is RowCountConstraint ||
            c is RowTransitionConstraint ||
            c is RowMajorityConstraint,
      );
      double maxWidth = contextWidth / game.currentPuzzle!.width;
      if (hasLeftBar) {
        maxWidth = contextWidth / (game.currentPuzzle!.width + 0.7);
      }
      double maxHeight = contextHeight / (game.currentPuzzle!.height + 2);
      cellSize = min(maxWidth, maxHeight);
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: _onDrawerChanged,
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
                    backgroundColor: Theme.of(
                      context,
                    ).extension<PuzzleColors>()!.validateButtonBg,
                    disabledBackgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceDim,
                    disabledForegroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryFixedDim,
                  ),
                  onPressed:
                      (game.currentPuzzle!.complete && !game.betweenPuzzles)
                      ? _manualValidate
                      : null,
                  icon: const Icon(Icons.check),
                  label: Text(
                    AppLocalizations.of(context)!.manuallyValidatePuzzle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (game.currentPuzzle != null &&
                !shouldChooseLocale &&
                game.currentPuzzle!.domain.length > 2)
              IconButton(
                icon: Icon(
                  _removeOptionMode
                      ? Icons.do_not_disturb_alt
                      : Icons.format_paint,
                ),
                tooltip: _removeOptionMode
                    ? AppLocalizations.of(context)!.tooltipTapModeRemoveOption
                    : AppLocalizations.of(context)!.tooltipTapModeIncrValue,
                onPressed: () {
                  setState(() => _removeOptionMode = !_removeOptionMode);
                },
              ),
            if (game.currentPuzzle != null && !shouldChooseLocale)
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: AppLocalizations.of(context)!.tooltipPuzzleHelp,
                onPressed: _showConstraintsHelp,
              ),
            if (game.currentPuzzle != null && !shouldChooseLocale)
              IconButton(
                key: _autopilotMode ? _hintButtonKey : null,
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
                // Don't restart immediately: pause and show the confirmation
                // overlay to guard against accidental taps (issue 21).
                onPressed: game.history.isEmpty
                    ? null
                    : () => setState(() {
                        _confirmingRestart = true;
                        game.pause();
                      }),
              ),
            if (database != null && !shouldChooseLocale)
              IconButton(
                icon: Icon(Icons.pause),
                tooltip: AppLocalizations.of(context)!.tooltipPause,
                onPressed: togglePause,
              ),
          ],
        ),
        drawer: MainDrawer(
          title: widget.title,
          versionText: versionText,
          authorText: 'Ghislain "court-jus" Lévêque',
          database: database,
          game: game,
          onLoadPuzzleSkipped: () => loadPuzzle(skipped: true),
          onSaveProgress: _saveProgress,
          onSharePuzzle: _sharePuzzle,
          onBrowse: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) =>
                  OpenPage(database: database!, onPuzzleSelected: openPuzzle),
            ),
          ),
          onGenerate: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => GeneratePage(
                database: database!,
                onPuzzleSelected: openPuzzle,
              ),
            ),
          ),
          onCreate: _openCreatePage,
          onStats: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => StatsPage(database: database!),
            ),
          ),
          onLearning: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) =>
                  LearningPage(database: database!, progress: progress),
            ),
          ),
          onSettings: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsPage(
                  settings: settings,
                  statsDirectoryError: database?.statsDirectoryError,
                  onReplayOnboarding: () async {
                    // Restart the onboarding journey end-to-end.
                    // Play stats are deliberately preserved — only
                    // the discovery overlay (firstSeen + strict
                    // phase counter), the open-page filters and
                    // the loaded collection are reset, and the
                    // in-progress puzzle is dropped (it could be
                    // from any collection — typically an expert
                    // puzzle the player wandered into — and has no
                    // place in a freshly-strict P0 playlist).
                    if (database != null) {
                      await database!.resetOnboardingProgress();
                      // Restore open-page state to first-launch
                      // defaults: a stale filter would otherwise
                      // gate the freshly-strict P0 catalog (e.g.
                      // `wantedRules={EY}` would hide the FM
                      // puzzles phase 0 needs). Persist filters
                      // BEFORE loadPuzzlesFile — that call re-
                      // loads them from prefs.
                      database!.currentFilters = Filters();
                      await database!.currentFilters.save();
                      await database!.setShouldShuffle(false);
                      await database!.loadPuzzlesFile(
                        Database.entryCollectionKey,
                      );
                      // `firstSeen` must be cleared AFTER
                      // loadPuzzlesFile: that call's internal
                      // loadStats() re-populates the map from
                      // history, so a clear() done earlier is
                      // silently undone — and the new-rule modal
                      // would then never re-fire on the P0 puzzle.
                      progress.clear();
                      await progress.save();
                      // Defensive: ensure the playlist is rebuilt
                      // with the now-empty firstSeen and reset
                      // counter in scope, even if a future change
                      // to loadPuzzlesFile drops its trailing
                      // preparePlaylist() call.
                      database!.preparePlaylist();
                      // Drop whatever puzzle was on screen and
                      // hand the player a fresh P0 pick from the
                      // rebuilt 1-easy playlist.
                      game.clearPuzzle();
                      loadPuzzle();
                    }
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
                      game.idleTimeoutDuration = settings.idleTimeoutDuration;
                      game.rearmIdleTimer();
                    }
                    if (newValue.nextPuzzleDelay != null) {
                      // Switching away from manual mid-solve: finalize the
                      // pending solved puzzle under the new mode instead of
                      // leaving a stale floating button / frozen stopwatch.
                      game.advanceIfManualNextPending(
                        settings,
                        _onPuzzleCompleted,
                      );
                    }
                    if (newValue.grayoutEnabled != null) {
                      _applyGrayoutSetting();
                      setState(() {});
                    }
                    if (newValue.themeMode != null) {
                      widget.setAppTheme(settings.themeMode);
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
                      // Defer the playlist recompute + puzzle reload to when the
                      // Settings page closes (see `onSettings`): doing it inline
                      // here would recompute on every slider commit and could
                      // surface onboarding modals on top of the menu.
                      _playlistDirty = true;
                    }
                    game.refresh();
                  },
                  onStatsDirectoryChanged: (path) async {
                    if (database == null) return;
                    if (path == null) {
                      // Flush the merged history (custom dir + legacy) back
                      // to the legacy location before dropping the reference,
                      // so plays made while the custom dir was active are not
                      // orphaned when it stops being read.
                      await database!.writeStatsToDefaultLocation();
                      await settings.setStatsDirectory(null);
                      database!.statsDirectory = null;
                      database!.statsDirectoryError = null;
                      // Reload stats from default-only storage now — this
                      // re-parses entry state and recomputes auto-level.
                      await _reloadStatsAndLevel();
                      if (!context.mounted) return;
                      setState(() {});
                      return;
                    }
                    await settings.setStatsDirectory(path);
                    database!.statsDirectory = path;
                    database!.statsDirectoryError = null;
                    final valid = await database!.validateStatsDirectory();
                    if (!valid) {
                      await database!.clearStatsDirectory();
                      await settings.setStatsDirectory(null);
                      // Reload stats after falling back to the default
                      // directory (the merged history has been flushed).
                      await _reloadStatsAndLevel();
                      if (!context.mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(
                              context,
                            )!.statsSyncDirectoryInvalid,
                          ),
                          duration: const Duration(seconds: 6),
                        ),
                      );
                      return;
                    }
                    // The directory is valid — reload stats so the new
                    // directory's entries are reflected immediately.
                    await _reloadStatsAndLevel();
                    if (!context.mounted) return;
                    setState(() {});
                  },
                  onChangeLanguage: () {
                    setState(() {
                      shouldChooseLocale = true;
                    });
                  },
                ),
              ),
            );
            // Recompute the playlist (and hand out the next puzzle) once, now
            // that the menu is closed — a level change inside Settings only
            // marked it dirty. Running it here also lets the new-rule modal
            // fire on the puzzle screen rather than over the Settings route.
            if (_playlistDirty && database != null) {
              _playlistDirty = false;
              database!.preparePlaylist();
              loadPuzzle();
            }
          },
          onHelp: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => HelpPage(locale: locale)),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, viewportConstraints) {
            // Anchor the puzzle to the bottom while playing so hint messages
            // appearing above don't push the grid down. In modal-like states
            // (pause, between puzzles, loading, locale picker) center instead,
            // since there's no grid to stabilise.
            final hasActivePuzzle =
                initialized &&
                !shouldChooseLocale &&
                !game.betweenPuzzles &&
                !game.paused &&
                game.currentPuzzle != null;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewportConstraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisAlignment: hasActivePuzzle
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 2,
                      children: <Widget>[
                        Text(
                          game.topMessage,
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                game.topMessageColor ??
                                Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        (initialized && !shouldChooseLocale)
                            ? Stack(
                                alignment: AlignmentGeometry.center,
                                children: [
                                  if (game.betweenPuzzles)
                                    BetweenPuzzles(
                                      like: like,
                                      loadPuzzle: loadPuzzle,
                                    )
                                  else if (game.paused)
                                    PauseOverlay(
                                      onResume: togglePause,
                                      onRestart: _confirmingRestart
                                          ? _confirmRestart
                                          : null,
                                      restartLabel: AppLocalizations.of(
                                        context,
                                      )!.restart,
                                      width: contextWidth,
                                      height: contextHeight,
                                      iconSize: cellSize * 3,
                                      subtitle: _pauseSubtitle(context),
                                    )
                                  else
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
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
                                            onCellLongPress:
                                                handlePuzzleLongPress,
                                            cellSize: cellSize,
                                            hintText: game.hintText,
                                            hintIsError: game.hintIsError,
                                            autopilotMode: _autopilotMode,
                                            onStateReady: _autopilotMode
                                                ? (s) => _puzzleWidgetState = s
                                                : null,
                                          )
                                        else
                                          Builder(
                                            builder: (context) {
                                              final l = AppLocalizations.of(
                                                context,
                                              )!;
                                              final labels =
                                                  CollectionLabels.fromLocalizations(
                                                    l,
                                                  );
                                              final recommendedKey = database
                                                  ?.recommendedCollectionKey;
                                              return EndOfPlaylist(
                                                currentLevel:
                                                    settings.playerLevel,
                                                filtersBlocking:
                                                    database
                                                        ?.areFiltersBlocking ??
                                                    false,
                                                hasMoreInCurrent:
                                                    database
                                                        ?.hasMoreCandidatesInCurrentCollection() ??
                                                    false,
                                                playedCount:
                                                    database?.puzzles
                                                        .where((p) => p.played)
                                                        .length ??
                                                    0,
                                                onboardingActive:
                                                    database?.isInOnboarding ??
                                                    false,
                                                currentCollectionLabel: labels
                                                    .labelFor(
                                                      database?.collection ??
                                                          '',
                                                    ),
                                                recommendedCollectionLabel:
                                                    recommendedKey == null
                                                    ? null
                                                    : labels.labelFor(
                                                        recommendedKey,
                                                      ),
                                                onContinueCurrent: () {
                                                  if (database == null) return;
                                                  database!.preparePlaylist();
                                                  if (database!
                                                      .playlist
                                                      .isNotEmpty) {
                                                    loadPuzzle();
                                                  }
                                                  setState(() {});
                                                },
                                                onSwitchToRecommended:
                                                    recommendedKey == null
                                                    ? null
                                                    : () async {
                                                        if (database == null) {
                                                          return;
                                                        }
                                                        await database!
                                                            .loadPuzzlesFile(
                                                              recommendedKey,
                                                            );
                                                        if (database!
                                                            .playlist
                                                            .isNotEmpty) {
                                                          loadPuzzle();
                                                        }
                                                        setState(() {});
                                                      },
                                                onPickAnother: () {
                                                  if (database == null) return;
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute<void>(
                                                      builder: (context) =>
                                                          OpenPage(
                                                            database: database!,
                                                            onPuzzleSelected:
                                                                openPuzzle,
                                                          ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                ],
                              )
                            : (shouldChooseLocale
                                  ? InitialLocaleChooser(
                                      selectLocale: toggleLocale,
                                    )
                                  : Text("Loading...")),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
        // Manual-next mode: a solved puzzle waits for the player to tap the
        // "next" button instead of auto-advancing. Hidden while paused /
        // between puzzles so it never overlaps the overlays.
        floatingActionButton:
            (game.showNextFab &&
                initialized &&
                !shouldChooseLocale &&
                !game.betweenPuzzles &&
                !game.paused &&
                game.currentPuzzle != null)
            ? FloatingActionButton(
                tooltip: AppLocalizations.of(context)!.nextPuzzle,
                onPressed: () =>
                    game.advanceToNextPuzzle(settings, _onPuzzleCompleted),
                child: const Icon(Icons.arrow_forward),
              )
            : null,
      ),
    );
  }
}
