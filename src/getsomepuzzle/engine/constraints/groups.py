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
        return {"idx": idx, "size": size}

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width
