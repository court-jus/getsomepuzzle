// Convert assets/privacy.{en,fr,es}.md into standalone HTML pages and write
// them to web/privacy.{en,fr,es}.html so the Flutter web build picks them up
// and ships them in build/web/, which is what gh-pages publishes.
//
// Run locally with: dart run bin/build_privacy.dart
// In CI: invoked from the build-web job before `flutter build web`.

import 'dart:io';

// markdown is a dev_dependency: it's only used by this build-time script,
// not by the Flutter app at runtime, so it shouldn't be promoted to a
// runtime dependency just to silence the linter.
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

const _locales = ['en', 'fr', 'es'];

const _titles = {
  'en': 'Privacy Policy — Get Some Puzzle',
  'fr': 'Politique de confidentialité — Get Some Puzzle',
  'es': 'Política de Privacidad — Get Some Puzzle',
};

const _otherLanguagesLabel = {
  'en': 'Other languages:',
  'fr': 'Autres langues :',
  'es': 'Otros idiomas:',
};

const _languageNames = {'en': 'English', 'fr': 'Français', 'es': 'Español'};

const _css = '''
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  max-width: 720px;
  margin: 2rem auto;
  padding: 0 1rem;
  color: #222;
  background: #fafafa;
  line-height: 1.55;
}
h1 { color: #1976d2; border-bottom: 2px solid #1976d2; padding-bottom: 0.3rem; }
h2 { color: #455a64; margin-top: 2rem; }
em { color: #666; }
.lang-switch {
  font-size: 0.9rem;
  color: #555;
  margin-bottom: 1.5rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid #ddd;
}
.lang-switch a { color: #1976d2; text-decoration: none; margin: 0 0.25rem; }
.lang-switch a:hover { text-decoration: underline; }
@media (prefers-color-scheme: dark) {
  body { color: #e8e8e8; background: #1e1e1e; }
  h1 { color: #64b5f6; border-bottom-color: #64b5f6; }
  h2 { color: #b0bec5; }
  em { color: #aaa; }
  .lang-switch { color: #aaa; border-bottom-color: #444; }
  .lang-switch a { color: #64b5f6; }
}
''';

String _renderPage(String locale, String body) {
  final otherLinks = _locales
      .where((l) => l != locale)
      .map((l) {
        return '<a href="privacy.$l.html" hreflang="$l">${_languageNames[l]}</a>';
      })
      .join(' · ');

  return '''<!DOCTYPE html>
<html lang="$locale">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="index,follow">
<title>${_titles[locale]}</title>
<style>$_css</style>
</head>
<body>
<nav class="lang-switch">${_otherLanguagesLabel[locale]} $otherLinks</nav>
$body
</body>
</html>
''';
}

void main(List<String> args) {
  final webDir = Directory('web');
  if (!webDir.existsSync()) {
    stderr.writeln('web/ directory not found — run from the project root.');
    exit(1);
  }

  for (final locale in _locales) {
    final mdFile = File('assets/privacy.$locale.md');
    if (!mdFile.existsSync()) {
      stderr.writeln('Missing source file: ${mdFile.path}');
      exit(1);
    }
    final markdown = mdFile.readAsStringSync();
    final body = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    final outFile = File('web/privacy.$locale.html');
    outFile.writeAsStringSync(_renderPage(locale, body));
    stdout.writeln('Wrote ${outFile.path}');
  }
}
