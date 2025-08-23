import random

from ..utils import to_rows, to_columns
from .base import CellCentricConstraint
from ..constants import CONSTRAST


class ParityConstraint(CellCentricConstraint):
    slug = "PA"

    def __repr__(self):
        idx, side = self.parameters["idx"], self.parameters["side"]
        return (
            f"Cell {idx + 1} should have the same number "
            f"of odd and even numbers on its {side} "
            f"side{'s' if side in ('horizontal', 'vertical') else ''}"
        )

    def _check(self, puzzle, debug=False):
        # The given cell has the same number of odd and even numbers on
        # one of its side (or both, vertically or horizontally),
        # the given cell and side are defined in the parameters
        idx, side = self.parameters["idx"], self.parameters["side"]
        w, h = puzzle.width, puzzle.height
        # Find the right row for idx
        ridx = idx // w
        cidx = idx % w
        rows = to_rows(puzzle.state, w, h)
        row = rows[ridx]
        columns = to_columns(puzzle.state, w)
        column = columns[cidx]
        row_values_and_indices = [(idx, c.value) for idx, c in enumerate(row)]
        col_values_and_indices = [(idx, c.value) for idx, c in enumerate(column)]
        sides = []
        if side in ("left", "horizontal"):
            sides.append([v for (i, v) in row_values_and_indices if i < cidx])
        if side in ("right", "horizontal"):
            sides.append([v for (i, v) in row_values_and_indices if i > cidx])
        if side in ("top", "vertical"):
            sides.append([v for (i, v) in col_values_and_indices if i < ridx])
        if side in ("bottom", "vertical"):
            sides.append([v for (i, v) in col_values_and_indices if i > ridx])
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
        # { "idx" : 4, "side" : "left" or "horizontal" or "right" }
        width = puzzle.width
        height = puzzle.height
        choices = ["left", "right", "top", "bottom"]
        if width % 2 != 0:
            choices.append("horizontal")
        if height % 2 != 0:
            choices.append("vertical")
        side = random.choice(choices)
        if side in ("left", "right", "horizontal"):
            min_left = 2 if side in ("left", "horizontal") else 0
            max_right = width - 2 if side in ("right", "horizontal") else width
            # the side(s) we pick must have an even number of cells
            # so, because we are zero indexed, the index must be even
            possible_indices = [
                i for i in range(width) if min_left <= i <= max_right and i % 2 == 0
            ]
            if not possible_indices:
                raise ValueError("Cannot generate parity constraint")
            col = random.choice(possible_indices)
            row = random.randint(0, puzzle.height - 1)
            return {"idx": col + row * puzzle.width, "side": side}

        else:
            min_top = 2 if side in ("top", "vertical") else 0
            max_bottom = height - 2 if side in ("bottom", "vertical") else height
            possible_indices = [
                i for i in range(height) if min_top <= i <= max_bottom and i % 2 == 0
            ]
            if not possible_indices:
                raise ValueError("Cannot generate parity constraint")
            col = random.randint(0, puzzle.width - 1)
            row = random.choice(possible_indices)
            return {"idx": col + row * puzzle.width, "side": side}

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width

    def line_export(self):
        idx, side = self.parameters["idx"], self.parameters["side"]
        return f"{self.slug}:{idx}.{side}"

    @staticmethod
    def line_import(line):
        idx, side = line.split(".")
        return {"idx": int(idx), "side": side}
