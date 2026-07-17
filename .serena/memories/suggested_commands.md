# getsomepuzzle — Suggested Commands

```bash
# Dependencies
flutter pub get

# Run app (debug)
flutter run

# Tests
flutter test                          # All
flutter test test/<file>             # Single file
xvfb-run -a flutter test integration_test/ -d linux   # Integration (Linux)

# Lint / format / analyze
dart format .
flutter analyze

# Build targets
flutter build apk --release
flutter build web --base-href=/getsomepuzzle/
flutter build windows
flutter build linux
flutter build macos
flutter build ios
flutter build appbundle --release -PenableMinify=true

# MSIX packaging (Windows)
dart run msix:create

# Localization
flutter gen-l10n

# Launcher icons
dart run flutter_launcher_icons

# CLI puzzle tools
dart run bin/generate.dart -n 100 -o puzzles.txt        # Generate
dart run bin/generate.dart --check assets/default.txt   # Validate
dart run bin/generate.dart --read-stats <dir>           # Sort by difficulty
