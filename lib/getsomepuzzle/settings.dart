
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValidateType { manual, intermediate, automatic }

class ChangeableSettings {
  ValidateType? validateType;

  ChangeableSettings({
    this.validateType = ValidateType.intermediate,
  });
}

class Settings {
  ValidateType validateType;
  final log = Logger("Settings");

  Settings({
    this.validateType = ValidateType.intermediate,
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
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("settingsValidateType", validateType.name);
  }

  void change(ChangeableSettings newValue) {
    validateType = newValue.validateType ?? validateType;
    save();
  }
}