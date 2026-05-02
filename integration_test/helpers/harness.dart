import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory replacement for `path_provider` that points every "directory"
/// call at a fresh temp directory. Required because the app writes stats files
/// and reads custom playlists from the documents directory during startup.
class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProviderPlatform() : _temp = Directory.systemTemp.createTempSync();

  final Directory _temp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _temp.path;

  @override
  Future<String?> getApplicationSupportPath() async => _temp.path;

  @override
  Future<String?> getTemporaryPath() async => _temp.path;

  @override
  Future<String?> getDownloadsPath() async => _temp.path;
}

/// Drop-in setup for every integration test: mock platform plugins and seed
/// SharedPreferences with the given map (plus `"locale": "en"` so the app
/// skips the initial locale chooser).
///
/// Pass [customPuzzles] (one v2 line per entry) to land the test on a
/// deterministic puzzle sequence: the harness writes them to the
/// `custom` playlist file in the fake documents directory and forces
/// `collectionToLoad` to `custom` so the player opens the first one.
/// `custom` collection preserves insertion order (no shuffle, no level
/// sampling), so puzzle N+1 always follows puzzle N.
Future<void> prepareApp(
  Map<String, Object> prefs, {
  List<String>? customPuzzles,
}) async {
  final pathProvider = FakePathProviderPlatform();
  PathProviderPlatform.instance = pathProvider;

  // Pre-seed `constraintFirstSeen` so the New-Constraint modal never
  // appears during integration tests. Without this, a fresh-prefs run
  // would surface the modal as soon as the test puzzle loads, blocking
  // every subsequent tap until the OK button is found and tapped.
  // The seed simulates a veteran player who has already met every
  // currently-known slug.
  const allSlugs = [
    'FM',
    'PA',
    'GS',
    'LT',
    'QA',
    'SY',
    'DF',
    'SH',
    'CC',
    'GC',
    'NC',
    'EY',
  ];
  final firstSeenSeed = <String, String>{
    for (final s in allSlugs) s: '2020-01-01T00:00:00.000',
  };
  final seed = <String, Object>{
    'locale': 'en',
    'constraintFirstSeen': jsonEncode(firstSeenSeed),
    ...prefs,
  };
  if (customPuzzles != null && customPuzzles.isNotEmpty) {
    seed['collectionToLoad'] = 'custom';
    final docsPath = await pathProvider.getApplicationDocumentsPath();
    final dir = Directory(p.join(docsPath!, 'getsomepuzzle'));
    dir.createSync(recursive: true);
    File(
      p.join(dir.path, 'custom.txt'),
    ).writeAsStringSync('${customPuzzles.join('\n')}\n');
  }
  SharedPreferences.setMockInitialValues(seed);
}

/// Advance pump clock until the given [condition] is true or a generous
/// budget has elapsed. Used to let async startup work (asset load, stats
/// read, puzzle open) settle without blocking on infinite periodic timers.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 100),
  int maxSteps = 50,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
}

/// Set a generous test viewport (1024x1024, dpr=1.0) so the full puzzle grid
/// fits above the fold — otherwise bottom cells fall outside the hit-test
/// area. Automatically resets on teardown.
void setTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1024, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Open the current screen's Scaffold drawer and let the animation settle.
Future<void> openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
}

/// Fixture puzzles used by integration tests that need a deterministic
/// 3x3 (and optionally a 5x3 follow-up). Lines are migrated from the
/// retired tutorial.txt with `TX:` stripped — kept as fixtures so the
/// harness doesn't depend on a specific puzzle existing in `1-easy.txt`.
const fixture3x3 = 'v2_12_3x3_100000000_LT:A.0.2;LT:B.1.4_1:121121111_45';
const fixture5x3 =
    'v2_12_5x3_000120010200202_LT:A.6.11;LT:B.10.13_1:111121211212212_54';
