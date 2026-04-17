import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValidateType { manual, intermediate, automatic }

enum ShowRating { yes, no }

enum ShareData { yes, no }

enum LiveCheckType { all, count, complete }

enum HintType { deducibleCell, addConstraint }

class ChangeableSettings {
  ValidateType? validateType;
  ShowRating? showRating;
  LiveCheckType? liveCheckType;
  ShareData? shareData;
  HintType? hintType;

  ChangeableSettings({
    this.validateType,
    this.showRating,
    this.liveCheckType,
    this.shareData,
    this.hintType,
  });

  @override
  String toString() {
    return "Val: ${validateType?.name}; Sr: ${showRating?.name}; Liv: ${liveCheckType?.name}; Shar: ${shareData?.name}; Hint: ${hintType?.name}";
  }
}

class Settings {
  ValidateType validateType;
  ShowRating showRating;
  ShareData shareData;
  LiveCheckType liveCheckType;
  HintType hintType;

  final log = Logger("Settings");

  Settings({
    this.validateType = ValidateType.intermediate,
    this.showRating = ShowRating.yes,
    this.shareData = ShareData.yes,
    this.liveCheckType = LiveCheckType.complete,
    this.hintType = HintType.deducibleCell,
  });

  @override
  String toString() {
    return "Val: ${validateType.name}; Sr: ${showRating.name}; Liv: ${liveCheckType.name}; Shar: ${shareData.name}; Hint: ${hintType.name}";
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
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("settingsValidateType", validateType.name);
    prefs.setString("settingsLiveCheckType", liveCheckType.name);
    prefs.setString("settingsShowRating", showRating.name);
    prefs.setString("settingsShareData", shareData.name);
    prefs.setString("settingsHintType", hintType.name);
  }

  void change(ChangeableSettings newValue) {
    // print("change $newValue");
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
    save();
  }
}
