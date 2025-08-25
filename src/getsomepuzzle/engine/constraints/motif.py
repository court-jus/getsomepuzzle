import random
import re

from ..utils import to_grid
from .base import Constraint


class Motif(Constraint):

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug)
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
        return {"motif": motif}

    def conflicts(self, other):
        if "motif" not in other.parameters:
            return False

        smotif, omotif = self.parameters["motif"], other.parameters["motif"]
        if len(smotif) == len(omotif):
            return omotif == smotif
        if len(smotif) > len(omotif):
            return omotif in smotif
        return smotif in omotif

    def is_present(self, puzzle, debug=False):
        motif = self.parameters["motif"]
        grid = to_grid(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: int(cell.value)
        )
        rows = ["".join(map(str, row)) for row in grid]
        findings = {}
        if debug:
            print("ROWS", rows)
        for midx, motifline in enumerate(motif):
            m_re = re.compile(motifline)
            for ridx, row in enumerate(rows):
                if debug:
                    print(
                        f"Motif {midx}: {motifline}, check in {ridx}:{row} - Findings: {findings}"
                    )
                matches = [
                    charidx
                    for charidx, _ in enumerate(row)
                    if m_re.match(row[charidx:])
                    and (
                        midx == 0
                        or charidx in findings.get(midx - 1, {}).get(ridx - 1, [])
                    )
                ]
                if matches:
                    if debug:
                        print(f"Match ({midx}, {len(motif) - 1})")
                    if midx == len(motif) - 1:
                        if debug:
                            print("Check shows that motif is not respected")
                        return False
                    findings.setdefault(midx, {})[ridx] = matches
                    if debug:
                        print(f"Add finding. Now: {findings}")
                elif debug:
                    print("No match")

        return True

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

class ForbiddenMotif(Motif):
    slug = "FM"
    bg_color = "purple"

    def __repr__(self):
        motif = self.parameters["motif"]
        return f"Motif {motif} is forbidden"

    def _check(self, puzzle, debug=False):
        return super().is_present(puzzle, debug=debug)

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
        return not super().is_present(puzzle, debug=debug)

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width
