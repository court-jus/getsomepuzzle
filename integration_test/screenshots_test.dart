// Capture store screenshots through the integration_test harness.
//
// Invocation:
//   xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux
//
// Locale defaults to English; override with `LOCALE=fr` (or `es`) on the
// command line to capture another locale's screens. PNGs land under
// `marketing/screenshots/raw/<locale>_<NN>_<name>.png`.
//
// We bypass `binding.takeScreenshot()` because that path requires a
// platform-channel implementation that Flutter desktop doesn't ship —
// instead we walk the render tree to grab the topmost
// RenderRepaintBoundary and call `toImage` directly.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:getsomepuzzle/main.dart' as app;
import 'package:getsomepuzzle/widgets/cell.dart';

import 'helpers/harness.dart';

const _supportedLocales = {'en', 'fr', 'es'};

/// 5×8 fixture loaded from assets/1-easy.txt: CC + DF + GS + PA + SY all
/// in the same puzzle, partly pre-filled. Visually richer than the
/// 5×3 LetterGroup fixture and a good match for portrait phone aspect
/// ratios.
const _fixture5x8MultiRules =
    'v2_12_5x8_0001010000000100021000000000020200000000_'
    'CC:0.1.1;CC:2.1.5;CC:3.2.2;DF:1.right;DF:10.right;DF:32.down;'
    'GS:0.1;GS:24.1;GS:38.13;GS:5.11;'
    'PA:18.bottom;PA:22.left;PA:34.left;'
    'SY:14.5;SY:23.3;SY:23.4;SY:39.3'
    '_1:2121111112211122221221121221122211222221_30';

/// 1080×1920 portrait at dpr=2 → a 2160×3840 PNG, well within Play Store
/// and App Store ranges and easy to crop down to specific device aspect
/// ratios in post-processing. The grid is responsive enough that this
/// resolution renders without overflow.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Capture a PNG of the current frame.
///
/// Goes through the RenderView's root composited layer (an OffsetLayer)
/// rather than a single RenderRepaintBoundary. A boundary-based capture
/// only sees one subtree at a time — drawer overlay alone, or home
/// alone, or modal dialog alone — never the composed result the user
/// actually sees on screen. The root layer rasters every child layer in
/// composition order: home + drawer + dialog stacked the way Flutter
/// paints them.
Future<void> _capture(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer;
  if (layer is! OffsetLayer) {
    fail(
      'Unexpected RenderView root layer type ${layer.runtimeType} — '
      'cannot rasterize.',
    );
  }
  final ui.Image image = await layer.toImage(
    view.paintBounds,
    pixelRatio: tester.view.devicePixelRatio,
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();

  final out = File(p.join('marketing', 'screenshots', 'raw', '$name.png'));
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Wrote ${out.path} (${bytes.length} B)');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final localeEnv = Platform.environment['LOCALE'] ?? 'en';
  final locale = _supportedLocales.contains(localeEnv) ? localeEnv : 'en';

  group('Store screenshots ($locale)', () {
    testWidgets('rich grid', (tester) async {
      // Multi-constraint 5x8 puzzle: shows that the game is more than
      // single-rule grids. Renders a near-vertical grid on a phone-shaped
      // viewport, filling the screen well.
      await prepareApp(
        {'locale': locale},
        customPuzzles: [_fixture5x8MultiRules],
      );
      _setPhoneViewport(tester);
      app.main([]);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _capture(tester, '${locale}_01_rich_grid');
    });

    testWidgets('main drawer open', (tester) async {
      await prepareApp({'locale': locale}, customPuzzles: [fixture5x3]);
      _setPhoneViewport(tester);
      app.main([]);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await openDrawer(tester);
      await _capture(tester, '${locale}_02_drawer');
    });

    testWidgets('help page', (tester) async {
      await prepareApp({'locale': locale}, customPuzzles: [fixture5x3]);
      _setPhoneViewport(tester);
      app.main([]);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await openDrawer(tester);
      await tester.tap(find.byIcon(Icons.help));
      await tester.pumpAndSettle();
      await _capture(tester, '${locale}_03_help');
    });

    testWidgets('editor with constraint-type picker', (tester) async {
      // Open the in-app editor (CreatePage) with an empty grid, then tap
      // the first cell — `_onCellTap` calls `showConstraintTypePicker`
      // for unconstrained cells, which opens the dialog we want to
      // showcase.
      await prepareApp({'locale': locale}, customPuzzles: [fixture5x3]);
      _setPhoneViewport(tester);
      app.main([]);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await openDrawer(tester);
      // The drawer's "Library" section (containing the Edit/Create
      // entry) is collapsed by default — expand it before the icon
      // tap. Restrict the ExpansionTile finder to the drawer subtree:
      // with a puzzle loaded, the drawer shows three sections —
      // Current Puzzle (initiallyExpanded), Library, Progress — and
      // Library is the second ExpansionTile inside the Drawer.
      final drawerSections = find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(ExpansionTile),
      );
      await tester.tap(drawerSections.at(1));
      await tester.pumpAndSettle();

      // Edit icon now visible inside the drawer's Library section. Tap
      // it; the wrapping ListTile pops the drawer and pushes CreatePage.
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.byIcon(Icons.edit),
        ),
      );
      await tester.pumpAndSettle();

      // CreatePage opens on a dimensions form (two sliders + a "Start"
      // ElevatedButton with Icons.edit). Tap that button to enter the
      // editor proper, where the empty 4×4 grid materialises.
      await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.edit));
      await tester.pumpAndSettle();

      // Now tap (0,0) — `_onCellTap` triggers `showConstraintTypePicker`
      // for an unconstrained cell.
      await tester.tap(find.byType(CellWidget).first);
      await tester.pumpAndSettle();

      await _capture(tester, '${locale}_04_editor_rule_picker');
    });
  });
}
