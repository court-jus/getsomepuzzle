import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
Future<void> prepareApp(Map<String, Object> prefs) async {
  final seed = <String, Object>{'locale': 'en', ...prefs};
  SharedPreferences.setMockInitialValues(seed);
  PathProviderPlatform.instance = FakePathProviderPlatform();
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
