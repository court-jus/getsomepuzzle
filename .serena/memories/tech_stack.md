# getsomepuzzle — Tech Stack

## Primary (Flutter/Dart)

- **Language**: Dart (SDK ^3.10.0)
- **Framework**: Flutter (^3.41.0)
- **State management**: None — `StatefulWidget` + `setState` throughout
- **Localization**: `flutter_localizations` via ARB (`l10n.yaml` → `lib/l10n/`); locales: en, es, fr
- **CI**: GitHub Actions (`.github/workflows/ci.yml`) — manual trigger + push to master
- **Supported targets**: Android, iOS, Web, Windows, Linux, macOS

### Key dependencies
- `collection`, `path_provider`, `flutter_md`, `intl`, `shared_preferences`, `wakelock_plus`, `logging`, `font_awesome_flutter`, `unicons`, `share_plus`, `file_picker`, `url_launcher`, `cross_file`, `open_file`
- **Dev**: `flutter_test`, `integration_test`, `fake_async`, `flutter_lints`, `flutter_launcher_icons`, `msix`, `markdown`

## Stale Python (Beeware)

- `pyproject.toml` references Beeware 0.3.24 with Toga 0.5.0
- `src/getsomepuzzle/` has NO `.py` source files — only `__pycache__` bytecode remains
- The Python codebase is fully superseded by the Dart port; config is legacy

## Platform-specific notes

- **Windows MSIX**: configured in `pubspec.yaml` (`msix_config`), built via `dart run msix:create`
- **Web**: deployed to GitHub Pages at `/getsomepuzzle/` base href
- **Linux CI**: uses `xvfb-run` for integration tests
- **macOS**: universal build enabled
