import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/fmfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/gsall.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/gsgs.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltgs.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/pafm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/shgs.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/syfm.dart';

/// Factory list of all known complicity types. Each entry is invoked at
/// puzzle construction time and kept only when [Complicity.isPresent]
/// returns true for the puzzle.
List<Complicity> allComplicities() => <Complicity>[
  FMFMComplicity(),
  GSAllComplicity(),
  GSGSComplicity(),
  LTFMComplicity(),
  LTGSComplicity(),
  PAFMComplicity(),
  SHGSComplicity(),
  SYFMComplicity(),
];
