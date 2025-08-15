import random
import re

from ..utils import to_grid
from .base import Constraint
from ..constants import DOMAIN


class ForbiddenMotif(Constraint):
    def __repr__(self):
        motif = self.parameters["motif"]
        return f"Motif {motif} is forbidden"

    def check(self, puzzle):
        motif = self.parameters["motif"]
        grid = to_grid(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: int(cell.value)
        )
        rows = ["".join(map(str, row)) for row in grid]
        findings = {}
        for midx, motifline in enumerate(motif):
            for ridx, row in enumerate(rows):
                matches = [
                    m.start()
                    for m in re.finditer(motifline, row)
                    if midx == 0
                    or m.start() in findings.get(midx - 1, {}).get(ridx - 1, [])
                ]
                if matches:
                    if midx == len(motif) - 1:
                        return False
                    findings.setdefault(midx, {})[ridx] = matches

        return True

    @staticmethod
    def generate_random_parameters(puzzle):
        motifw = random.randint(1, min(3, puzzle.width))
        motifh = random.randint(1 if motifw > 1 else 2, min(3, puzzle.height))
        motif = [
            "".join([str(random.choice(DOMAIN)) for i in range(motifw)])
            for j in range(motifh)
        ]
        return {"motif": motif}

    def conflicts(self, other):
        if type(self) != type(other):
            return False

        smotif, omotif = self.parameters["motif"], other.parameters["motif"]
        if len(smotif) == len(omotif):
            return omotif == smotif
        if len(smotif) > len(omotif):
            return omotif in smotif
        return smotif in omotif

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width
