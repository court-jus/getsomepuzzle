// Re-export shim.
//
// The solution-geometry descriptors moved to
// `lib/getsomepuzzle/solution_geometry.dart` so the generator can share them
// for inline vector emission. This file keeps the historical
// `bin/_solution_geometry.dart` import working for `bin/detect_regular_solutions.dart`
// and `test/spectral_features_test.dart` unchanged.
export 'package:getsomepuzzle/getsomepuzzle/solution_geometry.dart';
