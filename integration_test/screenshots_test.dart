// Capture store screenshots through the integration_test harness.
//
// Invocation (one command regenerates everything):
//   xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux
//
// Coverage: 4 scenarios × 3 locales (en/fr/es) × 5 device profiles =
// 60 PNGs written under
//   marketing/screenshots/raw/<locale>/<device>/<NN>_<name>.png
//
// Each device profile sets `tester.view.physicalSize` to the store's
// target dimensions with `dpr=2.0`, so the rasterized PNG is a 2×
// supersample of the spec — better for visual review and downsamples
// cleanly to exact store dims via `convert -resize 50%`. Logical canvas
// (= physicalSize / dpr) stays at 540–1024 dp, matching what real
// phones/tablets/iPad use, so the layout doesn't break.
//
//   device          physicalSize    output PNG    store target
//   play_phone      1080×1920       2160×3840     1080×1920
//   play_tablet_7   1200×1920       2400×3840     1200×1920
//   play_tablet_10  1600×2560       3200×5120     1600×2560
//   iphone_67       1290×2796       2580×5592     1290×2796
//   ipad_129        2048×2732       4096×5464     2048×2732
//
// We bypass `binding.takeScreenshot()` because that path requires a
// platform-channel implementation that Flutter desktop doesn't ship —
// instead we rasterize the RenderView's root composited OffsetLayer so
// overlays (drawers, modal dialogs) appear behind the menu the way they
// do on a real device.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/main.dart' as app;
import 'package:getsomepuzzle/widgets/cell.dart';

import 'helpers/harness.dart';

const _locales = ['en', 'fr', 'es'];

class _Device {
  const _Device(this.name, this.physicalSize, this.dpr);
  final String name;
  final Size physicalSize;
  final double dpr;
}

const _devices = [
  _Device('play_phone', Size(1080, 1920), 2.0),
  _Device('play_tablet_7', Size(1200, 1920), 2.0),
  _Device('play_tablet_10', Size(1600, 2560), 2.0),
  _Device('iphone_67', Size(1290, 2796), 2.0),
  _Device('ipad_129', Size(2048, 2732), 2.0),
];

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

void _setViewport(WidgetTester tester, _Device device) {
  tester.view.physicalSize = device.physicalSize;
  tester.view.devicePixelRatio = device.dpr;
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
Future<void> _capture(
  WidgetTester tester,
  String locale,
  _Device device,
  String name,
) async {
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
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      fail('toByteData returned null for $locale/${device.name}/$name');
    }
    final bytes = byteData.buffer.asUint8List();

    final out = File(
      p.join(
        'marketing',
        'screenshots',
        'raw',
        locale,
        device.name,
        '$name.png',
      ),
    );
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
    debugPrint('Wrote ${out.path} (${bytes.length} B)');
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final locale in _locales) {
    for (final device in _devices) {
      group('Store screenshots ($locale / ${device.name})', () {
        testWidgets('rich grid', (tester) async {
          // Multi-constraint 5×8 puzzle: shows that the game is more
          // than single-rule grids. Renders a near-vertical grid on a
          // phone-shaped viewport, filling the screen well.
          await prepareApp(
            {'locale': locale},
            customPuzzles: [_fixture5x8MultiRules],
          );
          _setViewport(tester, device);
          app.main([]);
          await tester.pumpAndSettle(const Duration(seconds: 5));
          await _capture(tester, locale, device, '01_rich_grid');
        });

        testWidgets('main drawer open', (tester) async {
          await prepareApp({'locale': locale}, customPuzzles: [fixture5x3]);
          _setViewport(tester, device);
          app.main([]);
          await tester.pumpAndSettle(const Duration(seconds: 5));
          await openDrawer(tester);
          await _capture(tester, locale, device, '02_drawer');
        });

        testWidgets('help page', (tester) async {
          await prepareApp({'locale': locale}, customPuzzles: [fixture5x3]);
          _setViewport(tester, device);
          app.main([]);
          await tester.pumpAndSettle(const Duration(seconds: 5));
          await openDrawer(tester);
          await tester.tap(find.byIcon(Icons.help));
          await tester.pumpAndSettle();
          await _capture(tester, locale, device, '03_help');
        });

        testWidgets('editor with constraint-type picker', (tester) async {
          // Open the in-app editor (CreatePage) with an empty grid,
          // then tap the first cell — `_onCellTap` calls
          // `showConstraintTypePicker` for unconstrained cells, which
          // opens the dialog we want to showcase.
          await prepareApp({'locale': locale}, customPuzzles: [fixture5x3]);
          _setViewport(tester, device);
          app.main([]);
          await tester.pumpAndSettle(const Duration(seconds: 5));

          await openDrawer(tester);
          // The "Library" section (containing the Edit/Create entry) is
          // collapsed by default — find it by its localized title and
          // expand it. Looking up the label via AppLocalizations keeps
          // this stable both across locales (en/fr/es) and against
          // reordering of the drawer's other sections.
          final drawerContext = tester.element(find.byType(Drawer));
          final l10n = AppLocalizations.of(drawerContext)!;
          await tester.tap(
            find.widgetWithText(
              ExpansionTile,
              l10n.menuSectionLibrary.toUpperCase(),
            ),
          );
          await tester.pumpAndSettle();

          // Edit icon now visible inside the drawer's Library section.
          // Tap it; the wrapping ListTile pops the drawer and pushes
          // CreatePage.
          await tester.tap(
            find.descendant(
              of: find.byType(Drawer),
              matching: find.byIcon(Icons.edit),
            ),
          );
          await tester.pumpAndSettle();

          // CreatePage opens on a dimensions form (two sliders + a
          // "Start" ElevatedButton with Icons.edit). Tap that button
          // to enter the editor proper, where the empty 4×4 grid
          // materialises.
          await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.edit));
          await tester.pumpAndSettle();

          // Now tap (0,0) — `_onCellTap` triggers
          // `showConstraintTypePicker` for an unconstrained cell.
          await tester.tap(find.byType(CellWidget).first);
          await tester.pumpAndSettle();

          await _capture(tester, locale, device, '04_editor_rule_picker');
        });
      });
    }
  }
}
