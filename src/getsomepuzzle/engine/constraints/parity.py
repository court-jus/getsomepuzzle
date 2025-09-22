import random

from ..utils import to_rows, to_columns
from .base import CellCentricConstraint
from ..constants import CONSTRAST, EMPTY


class ParityConstraint(CellCentricConstraint):
    slug = "PA"

    def __repr__(self):
        indices, side = self.parameters["indices"], self.parameters["side"]
        idx = indices[0]
        return (
            f"Cell {idx + 1} should have the same number "
            f"of odd and even numbers on its {side} "
            f"side{'s' if side in ('horizontal', 'vertical') else ''}"
        )

    def conflicts(self, other):
        if not isinstance(other, ParityConstraint):
            return False

        # Parity only have one index
        if self.parameters["indices"][0] != other.parameters["indices"][0]:
            return False

        conflicting = {
            "left": ["horizontal", "right"],
            "right": ["horizontal", "left"],
            "top": ["vertical", "bottom"],
            "bottom": ["vertical", "top"],
            "horizontal": ["right", "left"],
            "vertical": ["bottom", "top"],
        }
        return other.parameters["side"] in conflicting[self.parameters["side"]]

    def get_cell_text(self):
        # ⬅ ⮕ ⬆ ⬇ ⬌ ⬍  ⬉ ⬈ ⬊ ⬋
        parity_icons = {
            "left": "⬅",
            "right": "⮕",
            "horizontal": "⬌",
            "top": "⬆",
            "bottom": "⬇",
            "vertical": "⬍",
        }
        return parity_icons[self.parameters["side"]]

    def _check(self, puzzle, debug=False):
        # The given cell has the same number of odd and even numbers on
        # one of its side (or both, vertically or horizontally),
        # the given cell and side are defined in the parameters
        indices, side = self.parameters["indices"], self.parameters["side"]
        idx = indices[0]
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
            if any(v == EMPTY for v in side):
                continue
            even = len([v for v in side if v % 2 == 0])
            odd = len([v for v in side if v % 2 != 0])
            if even != odd:
                return False
        return True

    def apply(self, puzzle):
        changed = False
        indices, side = self.parameters["indices"], self.parameters["side"]
        idx = indices[0]
        w, h = puzzle.width, puzzle.height
        ridx = idx // w
        cidx = idx % w
        if side in ("left", "right", "horizontal"):
            rows = to_rows(puzzle.state, w, h)
            row = rows[ridx]
            values_and_indices = [(idx, ridx, c.value) for idx, c in enumerate(row)]
        else:
            columns = to_columns(puzzle.state, w)
            column = columns[cidx]
            values_and_indices = [(cidx, idx, c.value) for idx, c in enumerate(column)]

        sides = []
        if side in ("left", "horizontal"):
            sides.append([(c, r, v) for (c, r, v) in values_and_indices if c < cidx])
        if side in ("right", "horizontal"):
            sides.append([(c, r, v) for (c, r, v) in values_and_indices if c > cidx])
        if side in ("top", "vertical"):
            sides.append([(c, r, v) for (c, r, v) in values_and_indices if r < ridx])
        if side in ("bottom", "vertical"):
            sides.append([(c, r, v) for (c, r, v) in values_and_indices if r > ridx])
        for side in sides:
            empty_cells = [v == EMPTY for (c, r, v) in side]
            if not any(empty_cells):
                continue
            if all(empty_cells):
                continue
            even = len([v for (c, r, v) in side if v != EMPTY and v % 2 == 0])
            odd = len([v for (c, r, v) in side if v!= EMPTY and v % 2 != 0])
            empty = empty_cells.count(True)
            size_per_parity = int(len(side) / 2)
            value = None
            if size_per_parity - even == empty:
                value = [v for v in puzzle.domain if v % 2 == 0][0]
            elif size_per_parity - odd == empty:
                value = [v for v in puzzle.domain if v % 2 != 0][0]
            if value is not None:
                for (c, r, v) in side:
                    if v != EMPTY:
                        continue
                    idx = r * w + c
                    changed |= puzzle.state[idx].set_value(value)
        return changed

    @staticmethod
    def generate_random_parameters(puzzle):
        # { "indices" : [4], "side" : "left" or "horizontal" or "right" }
        width = puzzle.width
        height = puzzle.height
        choices = ["left", "right", "top", "bottom"]
        if width % 2 != 0:
            choices.append("horizontal")
        if height % 2 != 0:
            choices.append("vertical")
        side = random.choice(choices)
        if side in ("left", "right", "horizontal"):
            possible_indices = [i for i in range(width)]
            if side in ("left", "horizontal"):
                possible_indices = [i for i in possible_indices if i >= 2 and i % 2 == 0]
            if side in ("right", "horizontal"):
                possible_indices = [i for i in possible_indices if i <= width - 2 and (width - 1 - i) % 2 == 0]
            if not possible_indices:
                raise ValueError("Cannot generate parity constraint")
            col = random.choice(possible_indices)
            row = random.randint(0, height - 1)
            return {"indices": [col + row * puzzle.width], "side": side}

        else:
            possible_indices = [i for i in range(height)]
            if side in ("top", "vertical"):
                possible_indices = [i for i in possible_indices if i >= 2 and i % 2 == 0]
            if side in ("bottom", "vertical"):
                possible_indices = [i for i in possible_indices if i <= height - 2 and (height - 1 - i) % 2 == 0]
            if not possible_indices:
                raise ValueError("Cannot generate parity constraint")
            col = random.randint(0, puzzle.width - 1)
            row = random.choice(possible_indices)
            return {"indices": [col + row * puzzle.width], "side": side}

    @staticmethod
    def generate_all_parameters(puzzle):
        w = puzzle.width
        h = puzzle.height
        for idx in range(len(puzzle.state)):
            ridx = idx // w
            cidx = idx % w
            left_size = cidx
            right_size = w - 1 - cidx
            top_size = ridx
            bottom_size = h - 1 - ridx
            if left_size % 2 == 0 and left_size > 0:
                yield {"indices": [idx], "side": "left"}
            if right_size % 2 == 0 and right_size > 0:
                yield {"indices": [idx], "side": "right"}
            if left_size % 2 == 0 and right_size % 2 == 0 and right_size > 0 and left_size > 0:
                yield {"indices": [idx], "side": "horizontal"}
            if top_size % 2 == 0 and top_size > 0:
                yield {"indices": [idx], "side": "top"}
            if bottom_size % 2 == 0 and bottom_size > 0:
                yield {"indices": [idx], "side": "bottom"}
            if top_size % 2 == 0 and bottom_size % 2 == 0 and bottom_size > 0 and top_size > 0:
                yield {"indices": [idx], "side": "vertical"}


    @staticmethod
    def maximum_presence(puzzle):
        return int((puzzle.width * puzzle.height) / 5)

    def line_export(self):
        indices, side = self.parameters["indices"], self.parameters["side"]
        idx = indices[0]
        return f"{self.slug}:{idx}.{side}"

    @staticmethod
    def line_import(line):
        idx, side = line.split(".")
        return {"indices": [int(idx)], "side": side}

    def signature(self):
        bilateral = "bi" if self.parameters["side"] in ("horizontal", "vertical") else "mo"
        return f"{self.slug}:{bilateral}"
