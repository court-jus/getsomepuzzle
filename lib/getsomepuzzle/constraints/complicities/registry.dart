import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltfm.dart';

/// All known complicity types. Each is tested against a puzzle
/// to determine if it applies.
final allComplicities = <Complicity>[
  LTFMComplicity(),
];
