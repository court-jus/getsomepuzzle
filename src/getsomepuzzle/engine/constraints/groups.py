import random
import re

from ..utils import to_grid, to_groups
from .base import CellCentricConstraint
from ..constants import DOMAIN


class GroupSize(CellCentricConstraint):
    def __repr__(self):
        idx, size = self.parameters["idx"], self.parameters["size"]
        return f"Group at {idx + 1} should be of size {size}"

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def _check(self, puzzle, debug=False):
        idx, size = self.parameters["idx"], self.parameters["size"]
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
                    print(f"Motif {midx}: {motifline}, check in {ridx}:{row} - Findings: {findings}")
                matches = [
                    charidx
                    for charidx, _ in enumerate(row)
                    if m_re.match(row[charidx:]) and (
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

    @staticmethod
    def generate_random_parameters(puzzle):
        maximum_group_size = int(puzzle.width * puzzle.height * 0.6)
        idx = random.randint(0, len(puzzle.state) - 1)
        size = random.randint(1, maximum_group_size)
        return {"idx": idx, "size": size}

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width
