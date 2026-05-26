# Ready to Publish — Pre-Submission Checklist

Status snapshot for the road to Play Store + App Store. Items at the top
are the remaining blockers; everything below `## Already done` is shipped.

---

## Accounts & infrastructure

- [ ] **Google Play Developer account** — $25 one-time. Required to access
      the Play Console.
- [ ] **Apple Developer account** — $99/year. Required for App Store Connect
      and to run the app on a physical iPhone via TestFlight.
- [ ] **Confirm GitHub Pages deploy** — push to `master`, wait for the
      `deploy-pages` workflow, verify
      `https://court-jus.github.io/getsomepuzzle/privacy.{en,fr,es}.html`
      returns 200 and renders correctly on mobile + desktop. The store
      forms ask for this URL verbatim.

## Android — release readiness

- [ ] **Production keystore + signing**.
      - Generate JKS (`keytool -genkey -v -keystore upload-keystore.jks ...`)
      - Create `android/key.properties` (NOT committed)
      - Add `signingConfigs.release` block in `android/app/build.gradle.kts`
        and point `buildTypes.release` to it instead of `debug`
      - Enroll in **Play App Signing** on first upload (recommended)
## iOS — release readiness

- [ ] **Register the bundle ID in your Apple Developer account**
      (`cc.leveque.getsomepuzzle`). Until then, archiving will fail at
      the signing step.
- [ ] **Configure signing in Xcode**.
      - Set `DEVELOPMENT_TEAM` (currently absent)
      - Keep `CODE_SIGN_STYLE = Automatic` for first submission, switch
        to manual later if needed
- [ ] **Verify Info.plist version fields** before archive:
      `CFBundleDisplayName`, `CFBundleShortVersionString`
      (currently sourced from pubspec via `$(FLUTTER_BUILD_NAME)`).
- [ ] **First build path**: `flutter build ipa --release` locally, then
      open `Runner.xcworkspace` in Xcode and use **Product → Archive →
      Distribute → App Store Connect**. CI iOS build is optional and
      requires macOS runners + provisioning profiles.

## Store metadata (both stores, 3 locales)

- [ ] **Promo video** — optional, both stores.

## Privacy & compliance forms

- [ ] **Play Console Data Safety form** — declare "no data collected,
      no data shared". The privacy policy URL field accepts the
      gh-pages URL once it's live.
- [ ] **App Store Connect Privacy Nutrition Label** — tick "Data Not
      Collected" across the board.
- [ ] **Content / age rating questionnaires** — answer once per store,
      logic puzzle ⇒ "Everyone" / "4+".
- [ ] **Export compliance** (App Store) — "Uses standard encryption
      exempt from export documentation" (HTTPS only).

## Recommended polish (non-blocking)

- [ ] **Beta channels** before going production: Play Internal Testing
      and TestFlight. Both let you smoke-test signing, install flow and
      OS-level permission prompts on real devices.

---

## Already done

- [x] **Final store screenshots** captured and committed under
      `marketing/screenshots/<locale>/<device>/<NN>_<name>.png`. One
      command — `xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux`
      — regenerates the full matrix: 4 scenarios (rich grid / drawer
      with pause overlay behind / help page / editor with rule-picker
      dialog over a live grid) × 3 locales (en / fr / es) × 5 device
      profiles (`play_phone` 1080×1920, `play_tablet_7` 1200×1920,
      `play_tablet_10` 1600×2560, `iphone_67` 1290×2796, `ipad_129`
      2048×2732) = 60 PNGs. Each profile sets `tester.view.physicalSize`
      to the store target with `dpr=2.0`, so raw PNGs are 2× supersamples
      under `marketing/screenshots/raw/<locale>/<device>/` (gitignored).
      Capture rasters the `RenderView`'s root `OffsetLayer` so drawer
      overlays and modal dialogs composite correctly with the screens
      behind them, and bypasses
      `IntegrationTestWidgetsFlutterBinding.takeScreenshot()` (which
      throws `MissingPluginException` on Flutter desktop). DEBUG banner
      disabled at the `MaterialApp` level so screenshots come out clean.
      `marketing/finalize_screenshots.sh` then downsamples raws 50% via
      ImageMagick into the tracked tree at exact store dimensions; it
      accepts an optional `<locale>` or `<locale>/<device>` scope to
      reprocess a subset.
- [x] **Marketing-friendly framing** — the "no data collected, no ads,
      no tracking, free and open source" pitch is present in every
      `marketing/play_store/<locale>/full_description.txt` and
      `marketing/app_store/<locale>/description.txt`, and on the Play
      Store feature graphic. Tone stays sober (no superlatives), the
      privacy stance is positioned as the actual differentiator versus
      other phone-puzzle apps in this category.
- [x] **Store-listing texts authored** in en / fr / es, structured under
      `marketing/play_store/<locale>/` and `marketing/app_store/<locale>/`
      so the layout matches what `fastlane supply` / `fastlane deliver`
      consume out of the box. Coverage:
      - Play: `title`, `short_description`, `full_description`,
        `changelogs/default`.
      - App Store: `name`, `subtitle`, `description`, `keywords`,
        `promotional_text`, `release_notes`, `privacy_url`,
        `support_url`, `marketing_url`.
      Tone is deliberately sober (no hype). Privacy URLs point at the
      locale-specific pages already deployed by the gh-pages workflow.
      All length budgets verified (titles ≤30, subtitles ≤30, short
      descriptions ≤80, keywords ≤100, promotional text ≤170, full
      descriptions well under the 4000-char cap). See `marketing/README.md`
      for the full table and re-render commands.
- [x] **Store icons + Play Store feature graphic generated** from
      `marketing/sample_3x3.svg` and `marketing/feature_graphic.svg`.
      `marketing/icon_512.png` (Play Store listing icon, 512×512) and
      `marketing/feature_graphic.png` (Play Store feature graphic,
      1024×500 from `marketing/feature_graphic.svg`) are both rendered
      by `bin/build_icons.sh` alongside `marketing/app_icon_1024.png`
      (the App Store icon and launcher-icon source). Inkscape is
      required — ImageMagick blurs these SVGs.
- [x] **AAB build job + R8 minification** wired into CI. The `build-aab`
      job in `.github/workflows/ci.yml` runs alongside the existing
      `build-apk` and produces the artefact uploaded to the Play Console
      (`build/app/outputs/bundle/release/app-release.aab`). It calls
      `flutter build appbundle --release -PenableMinify=true`; the
      property is read in `android/app/build.gradle.kts` and toggles
      `isMinifyEnabled` + `isShrinkResources` on the release buildType,
      pulling in `android/app/proguard-rules.pro` (Flutter-engine keep
      rules + a few `-dontwarn` entries for noisy transitive deps). The
      APK job stays minify-off so a sideloadable, easier-to-debug build
      remains available as a safety net.
- [x] **App launcher icon generated for every platform** from
      `marketing/sample_3x3.svg`. Re-rasterised in the v1.6.11–v1.6.12
      range from an updated `marketing/sample_3x3.svg`; every PNG under
      `android/app/src/main/res/mipmap-*`, `ios/Runner/Assets.xcassets`,
      `web/icons/`, and `windows/runner/resources/app_icon.ico` was
      regenerated and committed. The SVG is rasterized to
      `marketing/app_icon_1024.png` (full-bleed 1024×1024, opaque) via
      **Inkscape** — ImageMagick gives blurry results on this kind of
      SVG. `flutter_launcher_icons` (declared in `pubspec.yaml`) then
      fans the PNG out to:
      - Android `mipmap-mdpi/…/mipmap-xxxhdpi/ic_launcher.png`
      - iOS `Assets.xcassets/AppIcon.appiconset/Icon-App-*.png`
        (alpha stripped to satisfy the App Store)
      - Web `icons/Icon-{192,512,maskable-192,maskable-512}.png` plus a
        manifest update with `background_color`/`theme_color = #c0ebf1`
      - Windows `runner/resources/app_icon.ico`
      - Linux: the `.desktop` entry (`packaging/linux/getsomepuzzle.desktop`)
        already follows the XDG convention (`Icon=getsomepuzzle`);
        `packaging/linux/install.sh` now installs the SVG to
        `~/.local/share/icons/hicolor/scalable/apps/getsomepuzzle.svg` and
        refreshes the GTK icon cache, with matching cleanup on
        `--uninstall`.
      - `web/favicon.png` is refreshed manually from `Icon-192.png`.
      Re-run `bin/build_icons.sh` after editing `marketing/sample_3x3.svg`
      or `marketing/feature_graphic.svg` — the script handles the Inkscape
      rasterization step (1024 + 512 + feature graphic) and then calls
      `dart run flutter_launcher_icons` to fan the 1024 PNG out to every
      platform.
- [x] **Help-page text scrubbed of obsolete telemetry mentions**.
      `assets/help.{en,fr,es}.md` no longer claim the game "automatically
      sends" played-puzzle data — they now state plainly that nothing is
      collected automatically and stats stay on-device unless the player
      sends them manually via the Journal screen.
- [x] **Production bundle ID set to `cc.leveque.getsomepuzzle`** on both
      platforms — based on the user-owned `leveque.cc` domain (reverse
      DNS, all-lowercase, valid Java identifier on Android, no hyphens).
      - Android: `namespace` + `applicationId` in
        `android/app/build.gradle.kts`; `MainActivity.kt` relocated from
        `kotlin/com/example/getsomepuzzle_ng/` to
        `kotlin/cc/leveque/getsomepuzzle/` with its `package` line
        updated to match.
      - iOS: all six `PRODUCT_BUNDLE_IDENTIFIER` occurrences in
        `ios/Runner.xcodeproj/project.pbxproj` (Debug/Release/Profile
        for Runner + RunnerTests targets) updated; the trailing `Ng`
        artefact from a previous incomplete rename was dropped.
- [x] **All outbound network calls removed**. The `postMessage()` helper
      and its two call sites (`_onPuzzleCompleted`, `like()`) in
      `lib/main.dart` no longer exist; `package:http` is no longer a
      direct dependency.
- [x] **`ShareData` setting deleted**. The enum, the `Settings` field,
      its `SharedPreferences` persistence, the settings-page UI row and
      all `settingShareData*` l10n strings (en / fr / es) are gone — the
      knob became meaningless once telemetry was removed.
- [x] **Android `INTERNET` permission removed** from
      `android/app/src/main/AndroidManifest.xml`. The `debug` and
      `profile` manifests still declare it (needed for Flutter's
      hot-reload), so dev workflows are unaffected; only the release
      AAB ships permission-free.
- [x] **iOS privacy strings audit**. No `NS*UsageDescription` keys in
      `Info.plist` — none needed, since the app accesses no privacy-
      sensitive APIs.
- [x] **Privacy policy authored** in en / fr / es as
      `assets/privacy.{en,fr,es}.md`. Factual, declares no collection,
      no third-party SDKs, contact email `ghislain@leveque.cc`.
- [x] **Build-time HTML generation**. `bin/build_privacy.dart` reads
      the markdown sources and emits styled standalone HTML pages to
      `web/privacy.{en,fr,es}.html` (gitignored). The `build-web` CI
      job runs the script before `flutter build web`, so the pages are
      shipped inside `build/web/` and deployed by the existing gh-pages
      workflow to
      `https://court-jus.github.io/getsomepuzzle/privacy.{en,fr,es}.html`.
- [x] **In-app link to the privacy policy**. The help page has a "View
      privacy policy" button that opens the locale-appropriate URL via
      `url_launcher` in the system browser (no in-app web view).
- [x] **`CHANGELOG` initialised** at the repo root, following
      [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
      SemVer. Anchored at `[1.7.0] — TBD` as the first public release;
      pre-1.7 history is intentionally not backfilled (internal
      iteration, no audience). Future bumps update both `pubspec.yaml`
      and the per-locale `marketing/.../changelogs/default.txt` and
      `release_notes.txt` snippets that feed the store "What's New"
      fields. Date is set at tag time.
