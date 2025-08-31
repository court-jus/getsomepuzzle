import random
import re

from ..utils import to_grid, to_groups
from .base import CellCentricConstraint


class GroupSize(CellCentricConstraint):
    slug = "GS"

    def __repr__(self):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        return f"Group at {idx + 1} should be of size {size}"

    def get_cell_text(self):
        return self.parameters["size"]

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug=debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def _check(self, puzzle, debug=False):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        groups = to_groups(puzzle.state, puzzle.width, puzzle.height, lambda cell: cell.value)
        my_group = [grp for grp in groups if idx in grp]
        if len(my_group) != 1:
            raise RuntimeError("My group should exist")
        my_group = my_group[0]
        if debug:
            print(f"Does GRP@{idx+1}={size} ?", my_group)
        return len(my_group) == size

    @staticmethod
    def generate_random_parameters(puzzle):
        maximum_group_size = min(10, max(1, int(puzzle.width * puzzle.height * 0.2)))
        idx = random.randint(0, len(puzzle.state) - 1)
        size = random.randint(1, maximum_group_size)
        return {"indices": [idx], "size": size}

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width

    def line_export(self):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        return f"{self.slug}:{idx}.{size}"

    @staticmethod
    def line_import(line):
        idx, size = line.split(".")
        return {"indices": [int(idx)], "size": int(size)}
