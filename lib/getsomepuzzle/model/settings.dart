import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValidateType { manual, intermediate, automatic }

enum ShowRating { yes, no }

enum LiveCheckType { all, count, complete }

enum HintType { deducibleCell, addConstraint }

enum IdleTimeout { disabled, s5, s10, s30, m1, m2 }

/// Delay between the automatic check confirming the puzzle is solved and the
/// switch to the next puzzle. `manual` disables the auto-switch: a floating
/// "next" button is shown instead, and the player advances by tapping it.
enum NextPuzzleDelay { s1, s3, s10, manual }

enum ThemeModeType { system, light, dark }

class ChangeableSettings {
  ValidateType? validateType;
  ShowRating? showRating;
  LiveCheckType? liveCheckType;
  HintType? hintType;
  IdleTimeout? idleTimeout;
  NextPuzzleDelay? nextPuzzleDelay;
  int? playerLevel;
  bool? autoLevel;
  bool? grayoutEnabled;
  String? statsDirectory;
  ThemeModeType? themeMode;

  ChangeableSettings({
    this.validateType,
    this.showRating,
    this.liveCheckType,
    this.hintType,
    this.idleTimeout,
    this.nextPuzzleDelay,
    this.playerLevel,
    this.autoLevel,
    this.grayoutEnabled,
    this.statsDirectory,
    this.themeMode,
  });

  @override
  String toString() {
    return "Val: ${validateType?.name}; Sr: ${showRating?.name}; Liv: ${liveCheckType?.name}; Hint: ${hintType?.name}; Idle: ${idleTimeout?.name}; Next: ${nextPuzzleDelay?.name}; GrayoutOn: $grayoutEnabled";
  }
}

class Settings {
  ValidateType validateType;
  ShowRating showRating;
  LiveCheckType liveCheckType;
  HintType hintType;
  IdleTimeout idleTimeout;
  NextPuzzleDelay nextPuzzleDelay;
  int playerLevel;
  bool autoLevel;
  bool grayoutEnabled;
  String? statsDirectory;
  ThemeModeType themeMode;

  final log = Logger("Settings");

  Settings({
    this.validateType = ValidateType.intermediate,
    this.showRating = ShowRating.no,
    this.liveCheckType = LiveCheckType.complete,
    this.hintType = HintType.deducibleCell,
    this.idleTimeout = IdleTimeout.disabled,
    this.nextPuzzleDelay = NextPuzzleDelay.s1,
    this.playerLevel = 0,
    this.autoLevel = true,
    this.grayoutEnabled = true,
    this.statsDirectory,
    this.themeMode = ThemeModeType.system,
  });

  @override
  String toString() {
    return "Val: ${validateType.name}; Sr: ${showRating.name}; Liv: ${liveCheckType.name}; Hint: ${hintType.name}; Idle: ${idleTimeout.name}; Next: ${nextPuzzleDelay.name}";
  }

  /// Duration corresponding to the current [idleTimeout], or null when the
  /// feature is disabled.
  Duration? get idleTimeoutDuration {
    switch (idleTimeout) {
      case IdleTimeout.disabled:
        return null;
      case IdleTimeout.s5:
        return const Duration(seconds: 5);
      case IdleTimeout.s10:
        return const Duration(seconds: 10);
      case IdleTimeout.s30:
        return const Duration(seconds: 30);
      case IdleTimeout.m1:
        return const Duration(minutes: 1);
      case IdleTimeout.m2:
        return const Duration(minutes: 2);
    }
  }

  /// Delay before the automatic check moves on to the next puzzle after a
  /// solve, or null in [NextPuzzleDelay.manual] mode (the player advances via
  /// the "next" button instead).
  Duration? get nextPuzzleDelayDuration {
    switch (nextPuzzleDelay) {
      case NextPuzzleDelay.s1:
        return const Duration(seconds: 1);
      case NextPuzzleDelay.s3:
        return const Duration(seconds: 3);
      case NextPuzzleDelay.s10:
        return const Duration(seconds: 10);
      case NextPuzzleDelay.manual:
        return null;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String settingsValidateType =
        prefs.getString("settingsValidateType") ?? "intermediate";
    switch (settingsValidateType) {
      case "manual":
        validateType = ValidateType.manual;
      case "intermediate":
        validateType = ValidateType.automatic;
      case "automatic":
        validateType = ValidateType.automatic;
    }
    final String settingsLiveCheckType =
        prefs.getString("settingsLiveCheckType") ?? "complete";
    switch (settingsLiveCheckType) {
      case "all":
        liveCheckType = LiveCheckType.all;
      case "count":
        liveCheckType = LiveCheckType.count;
      case "complete":
        liveCheckType = LiveCheckType.complete;
    }
    final String settingsShowRating =
        prefs.getString("settingsShowRating") ?? "no";
    switch (settingsShowRating) {
      case "yes":
        showRating = ShowRating.yes;
      case "no":
        showRating = ShowRating.no;
    }
    final String settingsHintType =
        prefs.getString("settingsHintType") ?? "deducibleCell";
    switch (settingsHintType) {
      case "deducibleCell":
        hintType = HintType.deducibleCell;
      case "addConstraint":
        hintType = HintType.addConstraint;
    }
    final String settingsIdleTimeout =
        prefs.getString("settingsIdleTimeout") ?? "disabled";
    idleTimeout = IdleTimeout.values.firstWhere(
      (e) => e.name == settingsIdleTimeout,
      orElse: () => IdleTimeout.disabled,
    );
    final String settingsNextPuzzleDelay =
        prefs.getString("settingsNextPuzzleDelay") ?? "s1";
    nextPuzzleDelay = NextPuzzleDelay.values.firstWhere(
      (e) => e.name == settingsNextPuzzleDelay,
      orElse: () => NextPuzzleDelay.s1,
    );
    playerLevel = prefs.getInt("settingsPlayerLevel") ?? 0;
    autoLevel = prefs.getBool("settingsAutoLevel") ?? true;
    grayoutEnabled = prefs.getBool("settingsGrayoutEnabled") ?? true;
    statsDirectory = prefs.getString("settingsStatsDirectory");
    final String settingsThemeMode =
        prefs.getString("settingsThemeMode") ?? "system";
    themeMode = ThemeModeType.values.firstWhere(
      (e) => e.name == settingsThemeMode,
      orElse: () => ThemeModeType.system,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("settingsValidateType", validateType.name);
    prefs.setString("settingsLiveCheckType", liveCheckType.name);
    prefs.setString("settingsShowRating", showRating.name);
    prefs.setString("settingsHintType", hintType.name);
    prefs.setString("settingsIdleTimeout", idleTimeout.name);
    prefs.setString("settingsNextPuzzleDelay", nextPuzzleDelay.name);
    prefs.setInt("settingsPlayerLevel", playerLevel);
    prefs.setBool("settingsAutoLevel", autoLevel);
    prefs.setBool("settingsGrayoutEnabled", grayoutEnabled);
    if (statsDirectory != null) {
      prefs.setString("settingsStatsDirectory", statsDirectory!);
    } else {
      prefs.remove("settingsStatsDirectory");
    }
    prefs.setString("settingsThemeMode", themeMode.name);
  }

  void change(ChangeableSettings newValue) {
    if (newValue.validateType != null) {
      validateType = newValue.validateType!;
    }
    if (newValue.liveCheckType != null) {
      liveCheckType = newValue.liveCheckType!;
    }
    if (newValue.showRating != null) {
      showRating = newValue.showRating!;
    }
    if (newValue.hintType != null) {
      hintType = newValue.hintType!;
    }
    if (newValue.idleTimeout != null) {
      idleTimeout = newValue.idleTimeout!;
    }
    if (newValue.nextPuzzleDelay != null) {
      nextPuzzleDelay = newValue.nextPuzzleDelay!;
    }
    if (newValue.playerLevel != null) {
      playerLevel = newValue.playerLevel!;
    }
    if (newValue.autoLevel != null) {
      autoLevel = newValue.autoLevel!;
    }
    if (newValue.grayoutEnabled != null) {
      grayoutEnabled = newValue.grayoutEnabled!;
    }
    if (newValue.statsDirectory != null) {
      statsDirectory = newValue.statsDirectory;
    }
    if (newValue.themeMode != null) {
      themeMode = newValue.themeMode!;
    }
    save();
  }

  /// Set or clear the stats sync directory and persist immediately.
  /// Separate from [change] because [ChangeableSettings.statsDirectory]
  /// is a tri-state (null = unset, non-null = set) that doesn't map
  /// cleanly to the "null = unchanged" convention of [change].
  Future<void> setStatsDirectory(String? path) async {
    statsDirectory = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('settingsStatsDirectory', path);
    } else {
      await prefs.remove('settingsStatsDirectory');
    }
  }
}
