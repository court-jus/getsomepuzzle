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

// ── Per-puzzle constraint occurrence caps ──────────────────────────
//
// Generation-time limits on how many instances of a single constraint
// slug one puzzle may carry. Enforced by `Constraint.canBeAddedTo`
// (the generator's iterative loop and the easing pass) and by
// `bin/cleanup_collections.dart --slug-cap`, which quarantines legacy
// corpus puzzles that exceed them into `assets/too_many_im_fm.txt`.

/// Max FM (ForbiddenMotif) instances per puzzle, any grid size.
const int kMaxFmPerPuzzle = 4;

/// Max IM (Implication) instances per puzzle: the grid's average
/// dimension rounded down, `(width + height) ~/ 2`. Tunable: change
/// the divisor or rounding here.
int maxImPerPuzzle(int width, int height) => (width + height) ~/ 2;

/// Slugs subject to a per-puzzle occurrence cap. Iterated by
/// `bin/cleanup_collections.dart` and tests; keep in sync with
/// [maxSlugOccurrences].
const Set<String> cappedSlugsPerPuzzle = {'FM', 'IM'};

/// Max occurrences of [slug] in one puzzle of `width x height`;
/// `null` = unlimited. Single source of truth shared by the
/// generator/easing gate and the cleanup pass.
int? maxSlugOccurrences(String slug, int width, int height) {
  switch (slug) {
    case 'FM':
      return kMaxFmPerPuzzle;
    case 'IM':
      return maxImPerPuzzle(width, height);
    default:
      return null;
  }
}
