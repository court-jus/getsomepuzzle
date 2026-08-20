const cellSizeToFontSize = 44.0 / 64.0;
const minConstraintsInTopBarSize = 60.0;
const motifConstraintInTopBarFillRatio = 0.7;

// ── Public website URLs ────────────────────────────────────────────
//
// Only [kSiteBaseUrl] is a raw literal — every other URL in the app
// derives from it (or from [kPrivacyBaseUrl], hosted on a separate
// gh-pages domain). Keep all website URL literals in this file.

/// Root URL of the public website. The player guide lives at
/// `doc/{en,fr,es}/index.html`, per-constraint pages at
/// `doc/{en,fr,es}/<SLUG>.html`, and share links target `/play/`.
const kSiteBaseUrl = 'https://leveque.cc/getsomepuzzle';

/// Share links target this URL with a `?puzzle=<line>` query — works as
/// a browser fallback everywhere, and later as the App Links / Universal
/// Links target on mobile when set up.
const kShareBaseUrl = '$kSiteBaseUrl/play/';

/// Base URL of the online documentation (player guide, per-constraint
/// pages), one directory per locale.
const kDocBaseUrl = '$kSiteBaseUrl/doc';

/// Public URL where the privacy-policy HTML pages are hosted (one per
/// locale). The pages are generated at build-time from
/// `assets/privacy.{en,fr,es}.md` by `bin/build_privacy.dart`, copied
/// into `build/web/` by `flutter build web`, and deployed to gh-pages —
/// hence the different domain.
const kPrivacyBaseUrl = 'https://court-jus.github.io/getsomepuzzle';
