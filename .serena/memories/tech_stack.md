# Tech stack

- Language: Dart 3 (records, patterns, switch expressions used throughout), Flutter (SDK via `flutter` CLI).
- Package manager: pub (`pubspec.yaml`, lockfile committed).
- Key deps: `flutter_md` (markdown→widgets, no images), `url_launcher` (external links), `shared_preferences` (locale/onboarding/stats persistence), `intl`, `path_provider`, `file_picker`, `share_plus`, `font_awesome_flutter`, `unicons`, `logging`, `wakelock_plus`, `window_manager`, `flutter_localizations` (gen-l10n).
- L10n: ARB files in `lib/l10n/` (`app_en.arb` template with `@key` metadata blocks; fr/es files carry values only, no metadata), `l10n.yaml` config, generated `app_localizations{,_en,_es,_fr}.dart` via `flutter gen-l10n`.
- Tests: `flutter_test` (+ `integration_test/` for device tests). CI workflow runs only `flutter test`.
- Platforms: android, ios, linux, macos, windows, web; tests run on Linux desktop/WSL2.
- Dev docs tooling: `bin/` Dart scripts, `dart run bin/…`.