import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValidateType { manual, intermediate, automatic }

enum ShowRating { yes, no }

enum LiveCheckType { all, count, complete }

enum HintType { deducibleCell, addConstraint }

enum IdleTimeout { disabled, s5, s10, s30, m1, m2 }

class ChangeableSettings {
  ValidateType? validateType;
  ShowRating? showRating;
  LiveCheckType? liveCheckType;
  HintType? hintType;
  IdleTimeout? idleTimeout;
  int? playerLevel;
  bool? autoLevel;
  bool? grayoutEnabled;
  String? statsDirectory;

  ChangeableSettings({
    this.validateType,
    this.showRating,
    this.liveCheckType,
    this.hintType,
    this.idleTimeout,
    this.playerLevel,
    this.autoLevel,
    this.grayoutEnabled,
    this.statsDirectory,
  });

  @override
  String toString() {
    return "Val: ${validateType?.name}; Sr: ${showRating?.name}; Liv: ${liveCheckType?.name}; Hint: ${hintType?.name}; Idle: ${idleTimeout?.name}; GrayoutOn: $grayoutEnabled";
  }
}

class Settings {
  ValidateType validateType;
  ShowRating showRating;
  LiveCheckType liveCheckType;
  HintType hintType;
  IdleTimeout idleTimeout;
  int playerLevel;
  bool autoLevel;
  bool grayoutEnabled;
  String? statsDirectory;

  /// When `false`, the hint button (and the underlying solver-on-demand
  /// it triggers) is disabled. Lets the player opt out of in-app solving
  /// on very large grids ("boss" puzzles, 30×20+) where running the
  /// solver from the UI would lock the app for many seconds.
  bool hintsEnabled;

  /// When `false`, the per-tap `Puzzle.updateConstraintStatus` scan is
  /// skipped and every constraint stays at full opacity. Same intent as
  /// `hintsEnabled`: dodge solver-side work that scales poorly on
  /// large boss grids.
  bool grayoutEnabled;

  final log = Logger("Settings");

  Settings({
    this.validateType = ValidateType.intermediate,
    this.showRating = ShowRating.no,
    this.liveCheckType = LiveCheckType.complete,
    this.hintType = HintType.deducibleCell,
    this.idleTimeout = IdleTimeout.disabled,
    this.playerLevel = 0,
    this.autoLevel = true,
    this.grayoutEnabled = true,
    this.statsDirectory,
  });

  @override
  String toString() {
    return "Val: ${validateType.name}; Sr: ${showRating.name}; Liv: ${liveCheckType.name}; Hint: ${hintType.name}; Idle: ${idleTimeout.name}; HintsOn: $hintsEnabled";
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
    playerLevel = prefs.getInt("settingsPlayerLevel") ?? 0;
    autoLevel = prefs.getBool("settingsAutoLevel") ?? true;
    grayoutEnabled = prefs.getBool("settingsGrayoutEnabled") ?? true;
    statsDirectory = prefs.getString("settingsStatsDirectory");
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("settingsValidateType", validateType.name);
    prefs.setString("settingsLiveCheckType", liveCheckType.name);
    prefs.setString("settingsShowRating", showRating.name);
    prefs.setString("settingsHintType", hintType.name);
    prefs.setString("settingsIdleTimeout", idleTimeout.name);
    prefs.setInt("settingsPlayerLevel", playerLevel);
    prefs.setBool("settingsAutoLevel", autoLevel);
    prefs.setBool("settingsGrayoutEnabled", grayoutEnabled);
    if (statsDirectory != null) {
      prefs.setString("settingsStatsDirectory", statsDirectory!);
    } else {
      prefs.remove("settingsStatsDirectory");
    }
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
