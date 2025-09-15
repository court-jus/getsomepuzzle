import random
import re

from ..utils import to_grid
from .base import Constraint


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
                    motif = [mline.replace(so, "0") for mline in motif]
                break

        return {"motif": motif}

    def conflicts(self, other):
        if "motif" not in other.parameters:
            return False

        smotif, omotif = self.parameters["motif"], other.parameters["motif"]
        if smotif == omotif[::-1]:
            return True
        if len(smotif) == len(omotif):
            if len(smotif) == 1:
                smo = smotif[0]
                omo = omotif[0]
                if smo == omo[::-1]:
                    return True
            return omotif == smotif
        if len(smotif) > len(omotif):
            return omotif in smotif
        return smotif in omotif

    def is_present(self, puzzle, debug=False):
        motif = self.parameters["motif"]
        pu = "".join(str(c.value) for c in puzzle.state)
        if debug:
            print("Find", motif, "in", pu)
        mow = len(motif[0])
        pta = puzzle.width - mow
        more = (pta * ".").join(motif).replace("0", ".")
        more = re.compile(more)
        for idx in range(len(pu)):
            if (puzzle.width - (idx % puzzle.width)) < mow:
                continue
            subst = pu[idx:]
            m = more.match(subst)
            if m:
                if debug:
                    print("found at", m.start())
                return True
        if debug:
            print("not found")
        return False

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
