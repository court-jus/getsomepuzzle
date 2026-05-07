// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/between_puzzles.dart';
import 'package:getsomepuzzle/widgets/end_of_playlist.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/learning_page.dart';
import 'package:getsomepuzzle/widgets/main_drawer.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/create_page.dart';
import 'package:getsomepuzzle/widgets/generate_page.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
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

const versionText = "Version 1.6.8";

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
  // Verbose only in debug builds, where we want to "watch" a play
  // session unfold: cell taps, validation outcomes, hint requests,
  // playlist transitions. Release builds stick to INFO so the player
  // sees a single "puzzle loaded" line per puzzle in their console
  // and nothing else while they play.
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
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
      debugShowCheckedModeBanner: false,
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
  final ConstraintProgress progress = ConstraintProgress();
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
    await progress.load();
    game.idleTimeoutDuration = settings.idleTimeoutDuration;
    futures.add(initializeDatabase(settings.playerLevel));
    futures.add(initializeLocale());
    await Future.wait(futures);
    // The database's stats load may have backfilled `progress` from
    // legacy plays — persist whatever new entries that produced so a
    // returning player doesn't have to re-derive them on every launch.
    await progress.save();
    initialized = true;
  }

  Future<void> initializeDatabase(int playerLevel) async {
    final db = Database(playerLevel: playerLevel, progress: progress);
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
    game.openPuzzle(
      puz,
      database!.playlist.length,
      progressRestoredText: AppLocalizations.of(context)!.progressRestored,
    );
    if (settings.hintType == HintType.addConstraint) {
      game.startHintConstraintComputation();
    }
    _surfaceNewConstraintsIfAny(puz);
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
    // A single puzzle line typically declares the same slug several
    // times (e.g. two FM: rules with different params). Build a Set
    // so each slug fires its modal section exactly once.
    final newSlugs = <String>{
      for (final slug in puz.rules)
        if (slug.isNotEmpty && slug != 'TX' && progress.isFirstTimeFor(slug))
          slug,
    };
    if (newSlugs.isEmpty) return;
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
        skipped = await NewConstraintDialog.show(
          context,
          newSlugs,
          showSkipButton: true,
        );
      }
      final now = DateTime.now();
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
        }
      }
      // Persist whatever new slugs were dismissed; failing silently
      // here only means the player will see the modal again next
      // launch (no game-state corruption).
      await progress.save();
      _modalInFlight = false;
      if (skipped && mounted) setState(() {});
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
      game.resume();
      if (game.currentPuzzle == null) {
        loadPuzzle();
      }
    } else {
      game.pause();
    }
  }

  void _onDrawerChanged(bool isOpened) {
    if (isOpened && game.currentPuzzle != null && !game.betweenPuzzles) {
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

  /// Localized name for a single constraint identified by its registry
  /// slug. Single source of truth for the constraint → l10n mapping;
  /// callers that hold a constraint instance route through the
  /// instance's `slug` getter.
  String _constraintNameBySlug(String slug) {
    final l10n = AppLocalizations.of(context)!;
    switch (slug) {
      case 'FM':
        return l10n.constraintForbiddenPattern;
      case 'SH':
        return l10n.constraintShape;
      case 'GS':
        return l10n.constraintGroupSize;
      case 'LT':
        return l10n.constraintLetterGroup;
      case 'PA':
        return l10n.constraintParity;
      case 'QA':
        return l10n.constraintQuantity;
      case 'SY':
        return l10n.constraintSymmetry;
      case 'DF':
        return l10n.constraintDifferentFrom;
      case 'CC':
        return l10n.constraintColumnCount;
      case 'GC':
        return l10n.constraintGroupCount;
      case 'NC':
        return l10n.constraintNeighborCount;
      case 'EY':
        return l10n.constraintEyes;
      case '*':
        return l10n.complicityOtherConstraint;
      default:
        // Hard fail in debug so the omission is caught in tests; keep
        // a graceful fallback in release rather than crashing the UI.
        assert(false, 'Unmapped constraint slug "$slug"');
        return slug;
    }
  }

  String _constraintName(CanApply givenBy) {
    if (givenBy is Constraint) return _constraintNameBySlug(givenBy.slug);
    // Unreachable for known sources (Complicity is handled at the call
    // site and routes through `slugs` instead).
    assert(false, 'Unexpected hint source ${givenBy.runtimeType}');
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
      hintDeducedFrom: (c) {
        if (c is Complicity) {
          final (s1, s2) = c.slugs;
          if (s1 == s2) {
            return l10n.hintComplicityTwin(_constraintNameBySlug(s1));
          }
          return l10n.hintComplicity(
            _constraintNameBySlug(s1),
            _constraintNameBySlug(s2),
          );
        }
        return l10n.hintDeducedFrom(_constraintName(c));
      },
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
    loadPuzzle();
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
    // invariant). Scheduled post-frame to avoid mutating state during build.
    if (game.currentPuzzle != null) {
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
            game.rotateCurrentPuzzle();
          });
        }
      }
    }

    double cellSize = 32.0;
    if (game.currentPuzzle != null) {
      final hasRC = game.currentPuzzle!.constraints
          .whereType<RowCountConstraint>()
          .isNotEmpty;
      double maxWidth = contextWidth / game.currentPuzzle!.width;
      if (hasRC) {
        maxWidth = contextWidth / (game.currentPuzzle!.width + 0.7);
      }
      double maxHeight = contextHeight / (game.currentPuzzle!.height + 2);
      cellSize = min(maxWidth, maxHeight);
    }

    return Scaffold(
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
            builder: (context) =>
                GeneratePage(database: database!, onPuzzleSelected: openPuzzle),
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
        onSettings: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SettingsPage(
              settings: settings,
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
                  await database!.loadPuzzlesFile(Database.entryCollectionKey);
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
              onChangeLanguage: () {
                setState(() {
                  shouldChooseLocale = true;
                });
              },
            ),
          ),
        ),
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
                          color: game.topMessageColor,
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
                                    width: contextWidth,
                                    height: contextHeight,
                                    iconSize: cellSize * 3,
                                    subtitle: _pauseSubtitle(context),
                                  )
                                else
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
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
                                          cellSize: cellSize,
                                          hintText: game.hintText,
                                          hintIsError: game.hintIsError,
                                        )
                                      else
                                        Builder(
                                          builder: (context) {
                                            final l = AppLocalizations.of(
                                              context,
                                            )!;
                                            final labels = CollectionLabels(
                                              easy: l.collectionEasy,
                                              player: l.collectionPlayer,
                                              advanced: l.collectionAdvanced,
                                              strong: l.collectionStrong,
                                              expert: l.collectionExpert,
                                              mad: l.collectionMad,
                                              myPuzzles: l.collectionMyPuzzles,
                                              recommendedTooltip: l
                                                  .tooltipRecommendedCollection,
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
                                                    database?.collection ?? '',
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
    );
  }
}
