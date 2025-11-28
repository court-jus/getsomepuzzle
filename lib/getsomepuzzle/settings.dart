
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValidateType { manual, intermediate, automatic }
enum LiveCheckType { all, count, complete }

class ChangeableSettings {
  ValidateType? validateType;
  LiveCheckType? liveCheckType;

  ChangeableSettings({
    this.validateType = ValidateType.intermediate,
    this.liveCheckType = LiveCheckType.complete,
  });
}

class Settings {
  ValidateType validateType;
  LiveCheckType liveCheckType;

  final log = Logger("Settings");

  Settings({
    this.validateType = ValidateType.intermediate,
    this.liveCheckType = LiveCheckType.complete,
  });

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String settingsValidateType = prefs.getString("settingsValidateType") ?? "intermediate";
    switch (settingsValidateType) {
      case "manual":
        validateType = ValidateType.manual;
      case "intermediate":
        validateType = ValidateType.intermediate;
      case "automatic":
        validateType = ValidateType.automatic;
    }
    final String settingsLiveCheckType = prefs.getString("settingsLiveCheckType") ?? "complete";
    switch (settingsLiveCheckType) {
      case "all":
        liveCheckType = LiveCheckType.all;
      case "count":
        liveCheckType = LiveCheckType.count;
      case "complete":
        liveCheckType = LiveCheckType.complete;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("settingsValidateType", validateType.name);
    prefs.setString("settingsLiveCheckType", liveCheckType.name);
  }

  void change(ChangeableSettings newValue) {
    validateType = newValue.validateType ?? validateType;
    liveCheckType = newValue.liveCheckType ?? liveCheckType;
    save();
  }
}