import random
import re

from ..utils import to_grid, to_groups
from .base import CellCentricConstraint
from ..constants import EMPTY
from ..errors import CannotApplyConstraint

AXIS = {
    1: "⟍",
    2: "|",
    3: "⟋",
    4: "―",
    5: "🞋",
}


class SymmetryConstraint(CellCentricConstraint):
    slug = "SY"

    def __repr__(self):
        indices, axis = self.parameters["indices"], self.parameters["axis"]
        idx = indices[0]
        return f"The cell at {idx + 1} should have symmetry along {AXIS[axis]}"

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug=debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def apply(self, puzzle, debug=False):
        # For each non free cell, if its symmetry is free, we can fill it
        indices, axis = self.parameters["indices"], self.parameters["axis"]
        idx = indices[0]
        my_color = puzzle.state[idx].value
        if my_color == EMPTY:
            return False
        groups = to_groups(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: cell.value
        )
        my_group = [grp for grp in groups if idx in grp]
        if len(my_group) != 1:
            return False
        my_group = my_group[0]

        changed = False
        for cellidx in my_group:
            c = puzzle.state[cellidx]
            sym = self._compute_symmetry(puzzle, cellidx, debug=debug)
            if sym is None:
                # The target cell is outside of the grid
                raise CannotApplyConstraint("The symmetry constraint cannot extend past the borders of the puzzle.")
            if puzzle.state[sym].free():
                # The target cell is free, set its value to my_color
                changed |= puzzle.set_value(sym, my_color)
        return changed

    def _check(self, puzzle, debug=False):
        indices, axis = self.parameters["indices"], self.parameters["axis"]
        idx = indices[0]
        my_color = puzzle.state[idx].value
        if my_color == EMPTY:
            return True
        groups = to_groups(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: cell.value
        )
        my_group = [grp for grp in groups if idx in grp]
        if len(my_group) != 1:
            return False
        my_group = my_group[0]

        if debug:
            print("My group", my_group)

        for cellidx in my_group:
            c = puzzle.state[cellidx]
            if debug:
                print("Check cell", cellidx + 1, my_color)
            sym = self._compute_symmetry(puzzle, cellidx, debug=debug)
            if sym is None:
                # The target cell is outside of the grid
                return False
            if puzzle.state[sym].free():
                # The target cell is free, no problem
                continue
            target = puzzle.state[sym]
            if debug:
                print(
                    f"  {sym + 1} = {target.value} {AXIS[axis]} {cellidx + 1} = {my_color}"
                )
            if target.value != my_color:
                return False
        return True

    def _compute_symmetry(self, puzzle, cellidx, debug=False):
        indices, axis = self.parameters["indices"], self.parameters["axis"]
        idx = indices[0]
        x, y = idx % puzzle.width, idx // puzzle.width
        cx, cy = cellidx % puzzle.width, cellidx // puzzle.width
        dx, dy = x - cx, y - cy
        if debug:
            print("   X", x, "Y", y, "cx", cx, "cy", cy)
            print("   Dx", dx, "Dy", dy)
        if axis == 1:
            # ⟍ symmetry
            sx, sy = x - dy, y - dx
        elif axis == 2:
            # | symmetry
            sx, sy = x + dx, cy
        elif axis == 3:
            # ⟋ symmetry
            sx, sy = x + dy, y + dx
        elif axis == 4:
            # ― symmetry
            sx, sy = cx, y + dy
        elif axis == 5:
            # 🞋 symmetry
            sx, sy = x + dx, y + dy
        newidx = sy * puzzle.width + sx
        if sx < 0 or sy < 0 or sx >= puzzle.width or sy >= puzzle.height:
            if debug:
                print(f" No target ({sx} {sy})")
            return None
        if debug:
            print(f" Target: ({sx} {sy}) {newidx + 1}")
        return newidx

    @staticmethod
    def generate_random_parameters(puzzle):
        min_count = 1
        max_count = (puzzle.width * puzzle.height) - 1
        return {
            "count": random.randint(min_count, max_count),
            "value": random.choice(puzzle.domain),
        }

    @staticmethod
    def generate_random_parameters(puzzle):
        idx = random.randint(0, len(puzzle.state) - 1)
        axis = random.choice(list(AXIS.keys()))
        return {"indices": [idx], "axis": axis}

    @staticmethod
    def generate_all_parameters(puzzle):
        for idx in range(len(puzzle.state)):
            for axis in AXIS:
                yield {"indices": [idx], "axis": axis}

    @staticmethod
    def maximum_presence(puzzle):
        return int((puzzle.width * puzzle.height) / 5)

    def line_export(self):
        indices, axis = self.parameters["indices"], self.parameters["axis"]
        idx = indices[0]
        return f"{self.slug}:{idx}.{axis}"

    @staticmethod
    def line_import(line):
        idx, axis = line.split(".")
        return {"indices": [int(idx)], "axis": int(axis)}

    def signature(self):
        axis = self.parameters["axis"]
        return f"{self.slug}:X.{axis}"
