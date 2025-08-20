import random

from ..utils import to_rows
from .base import CellCentricConstraint
from ..constants import CONSTRAST


class ParityConstraint(CellCentricConstraint):
    def __repr__(self):
        idx, side = self.parameters["idx"], self.parameters["side"]
        return (
            f"Cell {idx + 1} should have the same number "
            f"of odd and even numbers on its {side} "
            f"side{'s' if side == 'both' else ''}"
        )

    def _check(self, puzzle, debug=False):
        # The given cell has the same number of odd and even numbers on
        # one of its side (or both), the given cell and side are defined
        # in the parameters
        idx, side = self.parameters["idx"], self.parameters["side"]
        w, h = puzzle.width, puzzle.height
        # Find the right row for idx
        ridx = idx // w
        cidx = idx % w
        rows = to_rows(puzzle.state, w, h)
        row = rows[ridx]
        values_and_indices = [(idx, c.value) for idx, c in enumerate(row)]
        sides = []
        if side in ("left", "both"):
            sides.append([v for (i, v) in values_and_indices if i < cidx])
        if side in ("right", "both"):
            sides.append([v for (i, v) in values_and_indices if i > cidx])
        for side in sides:
            if any(v == 0 for v in side):
                continue
            even = len([v for v in side if v % 2 == 0])
            odd = len([v for v in side if v % 2 != 0])
            if even != odd:
                return False
        return True

    @staticmethod
    def generate_random_parameters(puzzle):
        # { "idx" : 4, "side" : "left" or "both" or "right" }
        choices = ["left", "right"]
        size = puzzle.width
        if size % 2 != 0:
            choices.append("both")
        side = random.choice(choices)
        min_left = 2 if side in ("left", "both") else 0
        max_right = size - 2 if side in ("right", "both") else size
        # the side(s) we pick must have an even number of cells
        # so, because we are zero indexed, the index must be even
        possible_indices = [
            i for i in range(size) if min_left <= i <= max_right and i % 2 == 0
        ]
        if not possible_indices:
            raise ValueError("Cannot generate parity constraint")
        col = random.choice(possible_indices)
        row = random.randint(0, puzzle.height - 1)
        return {"idx": col + row * puzzle.width, "side": side}

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width
