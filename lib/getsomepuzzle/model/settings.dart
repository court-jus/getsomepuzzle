import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValidateType { manual, intermediate, automatic }

enum ShowRating { yes, no }

enum ShareData { yes, no }

enum LiveCheckType { all, count, complete }

enum HintType { deducibleCell, addConstraint }

enum IdleTimeout { disabled, s5, s10, s30, m1, m2 }

class ChangeableSettings {
  ValidateType? validateType;
  ShowRating? showRating;
  LiveCheckType? liveCheckType;
  ShareData? shareData;
  HintType? hintType;
  IdleTimeout? idleTimeout;
  int? playerLevel;
  bool? autoLevel;

  ChangeableSettings({
    this.validateType,
    this.showRating,
    this.liveCheckType,
    this.shareData,
    this.hintType,
    this.idleTimeout,
    this.playerLevel,
    this.autoLevel,
  });

  @override
  String toString() {
    return "Val: ${validateType?.name}; Sr: ${showRating?.name}; Liv: ${liveCheckType?.name}; Shar: ${shareData?.name}; Hint: ${hintType?.name}; Idle: ${idleTimeout?.name}";
  }
}

class Settings {
  ValidateType validateType;
  ShowRating showRating;
  ShareData shareData;
  LiveCheckType liveCheckType;
  HintType hintType;
  IdleTimeout idleTimeout;
  int playerLevel;
  bool autoLevel;

  final log = Logger("Settings");

  Settings({
    this.validateType = ValidateType.intermediate,
    this.showRating = ShowRating.yes,
    this.shareData = ShareData.yes,
    this.liveCheckType = LiveCheckType.complete,
    this.hintType = HintType.deducibleCell,
    this.idleTimeout = IdleTimeout.disabled,
    this.playerLevel = 0,
    this.autoLevel = true,
  });

  @override
  String toString() {
    return "Val: ${validateType.name}; Sr: ${showRating.name}; Liv: ${liveCheckType.name}; Shar: ${shareData.name}; Hint: ${hintType.name}; Idle: ${idleTimeout.name}";
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
        prefs.getString("settingsShowRating") ?? "yes";
    switch (settingsShowRating) {
      case "yes":
        showRating = ShowRating.yes;
      case "no":
        showRating = ShowRating.no;
    }
    final String settingsShareData =
        prefs.getString("settingsShareData") ?? "yes";
    switch (settingsShareData) {
      case "yes":
        shareData = ShareData.yes;
      case "no":
        shareData = ShareData.no;
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
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("settingsValidateType", validateType.name);
    prefs.setString("settingsLiveCheckType", liveCheckType.name);
    prefs.setString("settingsShowRating", showRating.name);
    prefs.setString("settingsShareData", shareData.name);
    prefs.setString("settingsHintType", hintType.name);
    prefs.setString("settingsIdleTimeout", idleTimeout.name);
    prefs.setInt("settingsPlayerLevel", playerLevel);
    prefs.setBool("settingsAutoLevel", autoLevel);
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
    if (newValue.shareData != null) {
      shareData = newValue.shareData!;
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
    save();
  }
}
