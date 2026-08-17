// Render every constraint icon to a static PNG so surfaces that cannot
// run Flutter widgets (the website at leveque.cc/www/getsomepuzzle) can
// reference them.
//
// Invocation (from the repo root, regenerates everything):
//   xvfb-run -a flutter test integration_test/constraint_icons_test.dart -d linux
// or, with a display available:
//   flutter test integration_test/constraint_icons_test.dart -d linux
//
// Output, for each slug in `constraintUIRegistry` (n = 21):
//   assets/constraint_icons/<slug>.png        64dp rendered at 2x = 128px
//   assets/constraint_icons/<slug>-dark.png   same, dark-theme foreground
//
// The previews are the same widgets as the in-editor constraint-type
// picker (see lib/widgets/constraints/registry.dart); `ConstraintIcon`
// resolves the foreground from the ambient theme, so the light/dark pair
// comes from pumping the same widget under two themes. The output is
// transparent-backed, so the website can drop the glyphs on any surface.
//
// Regenerate whenever a preview widget changes or a new constraint slug
// is added to the UI registry — the files under assets/constraint_icons/
// are git-tracked.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';

final _boundaryKey = UniqueKey();

/// Logical size of the icon box; `toImage(pixelRatio: 2)` makes the PNG
/// twice as dense, so small devices / retina displays stay crisp.
const _iconSize = 64.0;

Future<void> _captureIcon(
  WidgetTester tester,
  String slug,
  Brightness brightness,
) async {
  final suffix = brightness == Brightness.dark ? '-dark' : '';
  final file = File(p.join('assets', 'constraint_icons', '$slug$suffix.png'));
  file.parent.createSync(recursive: true);

  await tester.pumpWidget(
    MaterialApp(
      // The preview widgets read the PuzzleColors theme extension, so
      // reuse the app's own themes rather than bare ThemeData.light()/dark().
      theme: brightness == Brightness.dark ? darkTheme : lightTheme,
      // Center gives the boundary loose constraints so it hugs the icon
      // instead of expanding to fill the (viewport-sized) home route.
      home: Center(
        child: RepaintBoundary(
          key: _boundaryKey,
          child: ConstraintIcon(slug: slug, size: _iconSize),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      fail('toByteData returned null for $slug$suffix');
    }
    file.writeAsBytesSync(byteData.buffer.asUint8List());
    debugPrint('Wrote ${file.path} (${byteData.lengthInBytes} B)');
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('constraint icons -> assets/constraint_icons/*.png', (
    tester,
  ) async {
    for (final entry in constraintUIRegistry) {
      await _captureIcon(tester, entry.slug, Brightness.light);
      await _captureIcon(tester, entry.slug, Brightness.dark);
    }
  });
}
