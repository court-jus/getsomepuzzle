# Cross-device stats synchronisation

Stats synchronisation lets the player point the app to an arbitrary
filesystem directory so a third-party file-sync tool (Syncthing,
Dropbox, etc.) can keep the stats file identical across devices. No
backend, no account, no cloud integration — the app only reads and
writes files in the chosen directory.

## Background

Stats are persisted as flat text files in
`ApplicationDocumentsDirectory/getsomepuzzle/` (native) or
`SharedPreferences` (web). Each line is a single play record (see
`StatEntry` in `lib/getsomepuzzle/model/stats.dart`). The canonical
file is `stats.txt`; imported files land as `stats_imported_<ts>.txt`.
The directory is not accessible from the platform file manager on
sandboxed OSes (Android/iOS), so the player cannot point a sync tool
at it directly.

## Mechanism

The player sets a directory path in **Settings → Stats sync directory**.
This path is stored as `Settings.statsDirectory` and persisted under
the `SharedPreferences` key `"settingsStatsDirectory"`. When set, the
app writes stats to `"<path>/stats.txt"` instead of the legacy
location. Reads scan both locations — the legacy dir and the sync
dir — so unsynced local backups are never lost.

### Read path

`Database._readRawStatsFromStorage()` enumerates `stats*` files from
both directories when `statsDirectory` is non-null:

```dart
// After reading from the legacy dir:
if (statsDirectory != null) {
  for (final entry in Directory(statsDirectory!).listSync()) {
    if (entry is! File || !p.basename(entry.path).startsWith("stats")) continue;
    // parse & add...
  }
}
```

Duplicates between the two sources are removed downstream by
`_mergedStatHistory` / `loadStats`, which key entries on
`(canonicalPuzzleKey, finishedTimestamp)`. The merge is idempotent —
a line present in both sources appears once.

### Write path

`Database.writeStats()` writes the merged history to
`<statsDirectory>/stats.txt` when `statsDirectory` is non-null, or to
the legacy path otherwise. The legacy dir is **never** written when a
custom dir is set, to avoid split-brain (the sync tool would otherwise
propagate the stale legacy file).

The legacy-only write logic lives in `_writeToLegacyDir(List<String>)`,
extracted so the migration safeguard (below) can reuse it.

### Import path

`Database.importStats(String content)` writes imported lines to
`"<statsDirectory>/stats_imported_<ts>.txt"` when `statsDirectory` is
non-null, else to the legacy dir. This follows the same pattern as
`writeStats`.

### Clear path

`Database.clearAllStats()` deletes every `stats*` file from **both**
the legacy directory and the custom directory (when set). A local
helper `clearStatsDir(String dirPath)` iterates the directory
synchronously and deletes matching files.

### Migration safeguard on clearing

When the player clears the **Stats sync directory** setting or picks a
different one, `main.dart`'s `onStatsDirectoryChanged` callback calls
`Database.writeStatsToDefaultLocation()` **before** updating the field:

```dart
onStatsDirectoryChanged: (path) async {
  if (path == null && database != null) {
    await database!.writeStatsToDefaultLocation();
  }
  await settings.setStatsDirectory(path);
  if (database != null) {
    database!.statsDirectory = path;
  }
},
```

`writeStatsToDefaultLocation()` reads the full merged history (from
both the about-to-be-orphaned custom dir and the legacy dir) and writes
it to `ApplicationDocumentsDirectory/getsomepuzzle/stats.txt`. This
guarantees every play survives even after the player reverts to the
default storage.

### UI: Settings page

`lib/widgets/settings_page.dart` contains `_StatsDirectoryRow`, a
private widget rendered below the **Clear all stats** button:

- Section header from `AppLocalizations.statsSyncDirectory`
- When a path is set: the path (elided to 2 lines) + **[Change]**
  **[Clear]** buttons
- When no path is set: just **[Choose folder]**
- On web: "Not available on web" message instead of buttons

The **Choose folder** / **Change** button calls
`FilePicker.getDirectoryPath()` (static method in file_picker 11.x).
The **Clear** button calls `onChange(null)`. The parent callback
`onStatsDirectoryChanged(String?)` is wired in `main.dart`.

## Setting: `statsDirectory`

`lib/getsomepuzzle/model/settings.dart`:

```dart
String? statsDirectory;
```

Persisted under the key `"settingsStatsDirectory"`. Loaded in
`Settings.load()`, saved in `Settings.save()` (null → remove). A
dedicated `setStatsDirectory(String?)` method exists separately from
`change(ChangeableSettings)` because the `ChangeableSettings` pattern
uses null to mean "unchanged", while for a nullable path null is a
valid value meaning "use the default location".

## Database field

`Database.statsDirectory` is a public field set by `main.dart` after
construction and on every settings change:

```dart
// In initializeDatabase:
db.statsDirectory = settings.statsDirectory;
```

The periodic `writeStats` timer and all other callers hold a reference
to `Database` and use this field directly.

## Behaviour matrix

| Player action | Read sources | Write target |
|---|---|---|
| Default (no custom dir) | Legacy dir only | Legacy dir |
| Set custom dir, play | Legacy dir + custom dir | Custom dir only |
| Clear custom dir | Both → merged → legacy (safeguard) | Legacy dir |
| Change to different dir | Legacy dir + new custom dir | New custom dir |

## Locale strings

Five keys were added to `lib/l10n/app_{en,fr,es}.arb`:

| Key | EN | FR | ES |
|---|---|---|---|
| `statsSyncDirectory` | Stats sync directory | Dossier de synchronisation | Directorio de sincronización |
| `statsSyncDirectoryChoose` | Choose folder | Choisir le dossier | Elegir carpeta |
| `statsSyncDirectoryChange` | Change | Changer | Cambiar |
| `statsSyncDirectoryClear` | Clear | Effacer | Borrar |
| `statsSyncDirectoryWebUnsupported` | Not available on web. | Non disponible sur le web. | No disponible en web. |

## In-game help

`assets/help.{en,fr,es}.md` — each locale's **Stats** section ends
with a paragraph linking to the published website page for the
corresponding language.

## Website pages

Published at `leveque.cc/www/getsomepuzzle/doc/{en,fr,es}/crossplay.html`,
following the same template as `learning.html`. They cover: feature
description, step-by-step setup, migration-on-clear, a Syncthing
walkthrough, and conflict resolution. Each locale's `index.html` nav
list includes a link.

## Platform differences

- **Native (Android, iOS, desktop)**: full support — the player picks
  a directory and the sync tool handles the rest.
- **Web**: not supported. `SharedPreferences` has no user-visible
  filesystem path. The UI shows a "Not available on web." message.

## Edge cases

- **Sync-tool conflict copies** (e.g. `stats.sync-conflict-…`). The
  read path picks up any file starting with `stats`, so conflict
  copies are merged on the next launch. Idempotent dedup means
  duplicates collapse harmlessly.
- **Directory becomes invalid** (SD card removed, network share
  unmounted). `writeStats` fails silently (the existing code does not
  throw on write errors). The player notices when stats appear to
  "reset" on other devices. Visual feedback for a missing directory
  is not implemented.
- **Partial write**. If the app crashes mid-write, a truncated line
  may be written. `Database.load()` skips malformed lines and logs
  the first 3 occurrences, so a partial write does not brick startup.

## File reference

| Path | Role |
|---|---|
| `lib/getsomepuzzle/model/settings.dart` | `statsDirectory` field + `setStatsDirectory()` |
| `lib/getsomepuzzle/model/database.dart` | Read/write/import/clear + `writeStatsToDefaultLocation()` |
| `lib/widgets/settings_page.dart` | `_StatsDirectoryRow` widget |
| `lib/main.dart` | Wire field + migration safeguard |
| `lib/l10n/app_{en,fr,es}.arb` | Localised labels |
| `assets/help.{en,fr,es}.md` | In-game help paragraph |
| `leveque.cc/www/getsomepuzzle/doc/{en,fr,es}/crossplay.html` | Website help pages |

## Non-goals

- **Puzzle sync** (`custom.txt`, `playlist_*.txt`). The same directory
  mechanism could be extended later but would need conflict resolution
  for mutable collections.
- **Settings sync**. `SharedPreferences` cannot be redirected to a
  file. Existing OS backup mechanisms (Android Auto Backup, iCloud)
  are the intended path.
- **In-app sync UI**. The app never shows sync status, peers, or
  triggers. The sync tool has its own interface.
