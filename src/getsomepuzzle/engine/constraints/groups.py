import random
import re

from ..constants import EMPTY
from ..utils import to_grid, to_groups, find_matching_group_neighbors, get_neighbors
from ..errors import CannotApplyConstraint
from .base import CellCentricConstraint

MAX_GS_RATIO = 0.5
MAX_GROUP_SIZE = 15


class GroupSize(CellCentricConstraint):
    slug = "GS"

    def __repr__(self):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        return f"Group at {idx + 1} should be of size {size}"

    def conflicts(self, other):
        if not isinstance(other, GroupSize):
            return False

        # Parity only have one index
        return self.parameters["indices"][0] == other.parameters["indices"][0]

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug=debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def _check(self, puzzle, debug=False):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        my_color = puzzle.state[idx].value
        if my_color == EMPTY:
            return True
        groups = to_groups(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: cell.value
        )
        my_group = [grp for grp in groups if idx in grp]
        if len(my_group) != 1:
            raise RuntimeError("My group should exist")
        my_group = my_group[0]
        if debug:
            print(f"Does GRP@{idx+1}={size} ?", my_group)
        if len(my_group) == size:
            return True
        if len(my_group) > size:
            return False
        # If my group is too small but there are still free cells, consider it ok
        return any(c.free() for c in puzzle.state)

    def apply(self, puzzle):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        # If my color is not known yet, return False
        my_color = puzzle.state[idx].value
        my_opposite = [v for v in puzzle.domain if v != my_color][0]
        if my_color == EMPTY:
            return False

        groups = to_groups(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: cell.value
        )
        my_group = [grp for grp in groups if idx in grp]
        if len(my_group) != 1:
            raise CannotApplyConstraint("My group should exist")
        my_group = my_group[0]
        boundaries = find_matching_group_neighbors(
            puzzle.state,
            puzzle.width,
            puzzle.height,
            my_group,
            EMPTY,
            lambda cell: cell.value,
        )
        changed = False
        if len(my_group) == size:
            # If my group already has the correct size, check my boundaries and set them to opposite color
            for boundary in boundaries:
                changed |= puzzle.state[boundary].set_value(my_opposite)
        elif len(my_group) < size:
            # If my group is not big enough yet but only has one exit, set it to my color
            if len(boundaries) == 1:
                boundary = boundaries[0]
                changed |= puzzle.state[boundary].set_value(my_color)
            elif len(boundaries) == 0:
                raise CannotApplyConstraint("I cannot grow and yet I'm not complete yet")
            else:
                # If extending in a direction would merge me with another group and create a "too big group",
                #   then add a boundary in that direction, it is forbidden to grow there
                margin = size - len(my_group)
                same_color_groups = [
                    cell
                    for grp in groups
                    for cell in grp
                    if any(puzzle.state[cell].value == my_color for cell in grp)
                    and not any(ind in grp for ind in indices)
                    and len(grp) >= margin
                ]
                # print("I'm", my_color,"scg", same_color_groups, "margin", margin)
                for boundary in boundaries:
                    boundary_neighbors = get_neighbors(puzzle.state, puzzle.width, puzzle.height, boundary)
                    # print(" bound", boundary, "has nei", boundary_neighbors)
                    if any(bound_nei in same_color_groups for bound_nei in boundary_neighbors):
                        # print("Cannot go there", boundary, "it would merge us with", same_color_groups)
                        changed |= puzzle.state[boundary].set_value(my_opposite)
        else:
            raise CannotApplyConstraint("My group is bigger than size")
        return changed

    @staticmethod
    def generate_random_parameters(puzzle):
        maximum_group_size = min(
            MAX_GROUP_SIZE, max(1, int(puzzle.width * puzzle.height * MAX_GS_RATIO))
        )
        idx = random.randint(0, len(puzzle.state) - 1)
        size = random.randint(1, maximum_group_size)
        return {"indices": [idx], "size": size}

    @staticmethod
    def generate_all_parameters(width, height, domain):
        maximum_group_size = min(
            MAX_GROUP_SIZE, max(1, int(width * height * MAX_GS_RATIO))
        )
        for idx in range(width * height):
            for size in range(1, maximum_group_size):
                yield {"indices": [idx], "size": size}

    @staticmethod
    def maximum_presence(w, h):
        return int((w * h) / 5)

    def line_export(self):
        indices, size = self.parameters["indices"], self.parameters["size"]
        idx = indices[0]
        return f"{self.slug}:{idx}.{size}"

    @staticmethod
    def line_import(line):
        idx, size = line.split(".")
        return {"indices": [int(idx)], "size": int(size)}

    def signature(self):
        size = self.parameters["size"]
        return f"{self.slug}:X.{size}"
