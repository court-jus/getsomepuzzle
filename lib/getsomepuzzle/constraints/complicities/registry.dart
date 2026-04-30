import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltfm.dart';

/// Factory list of all known complicity types. Each entry is invoked at
/// puzzle construction time and kept only when [Complicity.isPresent]
/// returns true for the puzzle.
List<Complicity> allComplicities() => <Complicity>[LTFMComplicity()];
