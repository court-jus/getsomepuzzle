import random
import re

from ..constants import EMPTY
from ..utils import to_grid, replace_char_at_idx
from ..errors import CannotApplyConstraint
from .base import Constraint

ALLOW_3x3_MOTIFS = False
ALLOW_3x2_MOTIFS = False
ALLOW_2x3_MOTIFS = False


class Motif(Constraint):

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug=debug)
        if self.ui_widget is not None:
            context = self.ui_widget.context
            with context.Stroke(
                color="green" if result else "red", line_width=4
            ) as stroke:
                stroke.rect(
                    x=2,
                    y=2,
                    width=self.ui_widget.width - 4,
                    height=self.ui_widget.height - 4,
                )
        return result

    @staticmethod
    def generate_random_parameters(puzzle):
        motifw = random.randint(1, min(3, puzzle.width))
        motifh = random.randint(1 if motifw > 1 else 2, min(3, puzzle.height))
        motif = [
            "".join([str(random.choice(puzzle.domain)) for i in range(motifw)])
            for j in range(motifh)
        ]
        for v in puzzle.domain:
            sv = str(v)
            allhave = all(sv in motifline for motifline in motif)
            start = any(motifline[0] == sv for motifline in motif)
            end = any(motifline[-1] == sv for motifline in motif)
            if allhave and start and end:
                for other in [o for o in puzzle.domain if o != v]:
                    so = str(other)
                    motif = [mline.replace(so, str(EMPTY)) for mline in motif]
                break

        return {"motif": motif}


    @staticmethod
    def generate_all_parameters(puzzle):
        w = puzzle.width
        h = puzzle.height

        all_11 = [str(EMPTY)] + [str(v) for v in puzzle.domain]
        all_12 = ["".join([i, j]) for i in all_11 for j in all_11]
        all_13 = ["".join([i, j]) for i in all_11 for j in all_12]
        all_21 = [[i, j] for i in all_11 for j in all_11]
        all_22 = [[i, j] for i in all_12 for j in all_12]
        all_23 = [[i, j] for i in all_13 for j in all_13]
        all_31 = [[i, j, k] for i in all_11 for j in all_11 for k in all_11]
        all_32 = [[i, j, k] for i in all_12 for j in all_12 for k in all_12]
        all_33 = [[i, j, k] for i in all_13 for j in all_13 for k in all_13]
        all_motifs = all_11 + all_12 + all_21 + all_22
        if w > 2:
            all_motifs = all_motifs + all_13
            if ALLOW_2x3_MOTIFS:
                all_motifs += all_23
        if h > 2:
            all_motifs = all_motifs + all_31
            if ALLOW_3x2_MOTIFS:
                all_motifs += all_32
            if w > 2 and ALLOW_3x3_MOTIFS:
                all_motifs = all_motifs + all_33
        for motif in all_motifs:
            if (
                all(i == str(EMPTY) for i in motif[0]) or
                all(i == str(EMPTY) for i in motif[-1]) or
                all(r[0] == str(EMPTY) for r in motif) or
                all(r[-1] == str(EMPTY) for r in motif)
            ):
                continue
            yield {"motif": motif}

    def conflicts(self, other):
        if "motif" not in other.parameters:
            return False

        smotif, omotif = self.parameters["motif"], other.parameters["motif"]
        basic_patterns = [
            ["11"], ["22"], ["1", "1"], ["2", "2"],
        ]
        if smotif in basic_patterns and omotif in basic_patterns:
            return True
        novice_patterns = [["12"], ["21"], ["1", "2"], ["2", "1"]]
        if (smotif in novice_patterns and omotif in basic_patterns) or (smotif in basic_patterns and omotif in novice_patterns):
            return True

        if Motif._is_present(smotif, "".join(omotif), len(omotif[0])):
            # smotif is present in omotif
            return True

        if Motif._is_present(omotif, "".join(smotif), len(smotif[0])):
            # omotif is present in smotif
            return True

        return False

    @staticmethod
    def _is_present(motif, strstate, width, debug=False):
        if debug:
            print("Find", motif, "in", strstate)
        mow = len(motif[0])
        pta = width - mow
        more = (pta * ".").join(motif).replace(str(EMPTY), ".")
        more = re.compile(more)
        for idx in range(len(strstate)):
            if (width - (idx % width)) < mow:
                continue
            subst = strstate[idx:]
            m = more.match(subst)
            if m:
                if debug:
                    print("found at", idx, "(", subst ,")", m.start())
                return True, idx
        if debug:
            print("not found")
        return False, None

    def is_present(self, puzzle, debug=False):
        motif = self.parameters["motif"]
        width = puzzle.width
        state = "".join(str(c.value) for c in puzzle.state)
        present, _ = Motif._is_present(motif, state, width, debug=debug)
        return present

    def line_export(self):
        motif = ".".join("".join(row) for row in self.parameters["motif"])
        return f"{self.slug}:{motif}"

    @staticmethod
    def line_import(line):
        lines = line.split(".")
        motif = [
            "".join([v for v in row])
            for row in lines
        ]
        return {"motif": motif}

    def signature(self):
        motif = ".".join("".join(row) for row in self.parameters["motif"])
        if "2" in motif and not "1" in motif:
            motif = motif.replace("2", "1")
        elif "2" in motif and "1" in motif:
            idx_1, idx_2 = motif.index("1"), motif.index("2")
            repl_1 = "A" if idx_1 < idx_2 else "B"
            repl_2 = "B" if idx_1 < idx_2 else "A"
            motif = motif.replace("1", repl_1).replace("2", repl_2)
        return f"{self.slug}:{motif}"

    @staticmethod
    def find_submotif(strmotif, puzzle, debug=False):
        if debug:
            print("all motifs", [
                (car, idx, strmotif[idx], replace_char_at_idx(strmotif, idx, str(EMPTY)))
                for idx, car in enumerate(strmotif)
            ])
        for idx, car, submotif in [
            (idx, strmotif[idx], replace_char_at_idx(strmotif, idx, str(EMPTY)))
            for idx, car in enumerate(strmotif)
            if car not in (str(EMPTY), ".")
        ]:
            if debug:
                print("Try submotif", submotif)
            present, where = Motif._is_present(submotif.split("."), "".join(str(c.value) for c in puzzle.state), puzzle.width)
            if present:
                return where, idx, car, submotif

    def apply(self, puzzle, debug=False):
        motif = self.parameters["motif"]
        strmotif = ".".join(motif)
        mow = len(motif[0])
        result = False
        changed = True
        while changed:
            submotif = Motif.find_submotif(strmotif, puzzle, debug=debug)
            if submotif is None:
                return False

            where, idx, car, submotif = submotif
            if debug:
                print("In the puzzle, at idx", where, "we found the submotif", submotif, "(that was built by replacing car", car, "at idx", idx, "in the main motif", ".".join(motif), ")")
            ridx = (idx // (mow + 1))
            cidx = (idx % (mow + 1))
            if debug:
                print("In the submotif, the car replaced was at", cidx, "x", ridx, "(I", idx, "M", mow, ")")
            wridx = (where // puzzle.width)
            wcidx = (where % puzzle.width)
            if debug:
                print("The stuff was found at", where, ":", wcidx, "x", wridx, "in the puzzle")
            fridx = wridx + ridx
            fcidx = wcidx + cidx
            fidx = fridx * puzzle.width + fcidx
            if debug:
                print("So the cell at", fidx, "(", fcidx, "x", fridx, ") cannot equal", car)
            if puzzle.state[fidx].value == int(car):
                raise CannotApplyConstraint(f"Cannot apply FM {motif} because {fidx + 1} == {int(car)}")
            opposite = [v for v in puzzle.domain if v != int(car)][0]
            changed = puzzle.state[fidx].set_value(opposite)
            result |= changed
        return result

class ForbiddenMotif(Motif):
    slug = "FM"
    bg_color = "purple"

    def __repr__(self):
        motif = self.parameters["motif"]
        return f"Motif {motif} is forbidden"

    def _check(self, puzzle, debug=False):
        return not super().is_present(puzzle, debug=debug)

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width


class RequiredMotif(Motif):
    slug = "RM"
    bg_color = "blue"

    def __repr__(self):
        motif = self.parameters["motif"]
        return f"Motif {motif} is required"

    def _check(self, puzzle, debug=False):
        return super().is_present(puzzle, debug=debug)

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width
