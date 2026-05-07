# ProGuard/R8 keep rules applied on top of the default optimized config
# (`proguard-android-optimize.txt`). Loaded only when the release buildType
# is built with `-PenableMinify=true` — see `build.gradle.kts`.

# --- Flutter engine ---------------------------------------------------------
# Keep the embedding entry points and plugin registry: R8 doesn't see the
# JNI-side references, so without these the app crashes on launch with a
# ClassNotFoundException.
-keep class io.flutter.app.**       { *; }
-keep class io.flutter.plugin.**    { *; }
-keep class io.flutter.util.**      { *; }
-keep class io.flutter.view.**      { *; }
-keep class io.flutter.**           { *; }
-keep class io.flutter.plugins.**   { *; }
-dontwarn io.flutter.embedding.**

# --- Play Core (deferred-components / split install) -----------------------
# We don't use deferred components, but the Flutter Gradle plugin still
# references this package; silence the warnings instead of pulling the
# library in.
-dontwarn com.google.android.play.core.**

# --- Standard noisy-but-harmless warnings ----------------------------------
-dontwarn javax.annotation.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
