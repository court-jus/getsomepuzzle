import random
import re

from ..utils import to_grid, to_groups, get_neighbors
from .base import CellCentricConstraint


class LetterGroup(CellCentricConstraint):
    slug = "LT"

    def __repr__(self):
        indices, letter = self.parameters["indices"], self.parameters["letter"]
        human_readable_indices = [idx + 1 for idx in indices]
        return f"Group at {human_readable_indices} should have letter {letter}"

    def conflicts(self, other):
        if not isinstance(other, CellCentricConstraint):
            return False

        # Another rule with the same letter does not conflict, it just adds up to the constraint
        if isinstance(other, LetterGroup) and other.parameters["letter"] == self.parameters["letter"]:
            return False

        return any(idx in other.parameters["indices"] for idx in self.parameters["indices"])

    def get_cell_text(self):
        return self.parameters["letter"]

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug=debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def _check(self, puzzle, debug=False):
        indices, letter = self.parameters["indices"], self.parameters["letter"]
        # If any of my cells are not filled yet, there's no need to check further
        if any(c.free() for idx, c in enumerate(puzzle.state) if idx in indices):
            return True
        groups = to_groups(puzzle.state, puzzle.width, puzzle.height, lambda cell: cell.value)
        if debug:
            print("Check LT", self, "Groups:", groups)
        my_groups = []
        for group in groups:
            intersect = set(group).intersection(set(indices))
            if intersect:
                my_groups.append(group)
        # There should be no other letter in mygroup
        my_group = my_groups[0]
        letters_in_my_group = []
        for idx in my_group:
            letters_in_my_group.extend([
                c.parameters["letter"] for c in puzzle.constraints
                if isinstance(c, LetterGroup) and idx in c.parameters["indices"]
            ])
        if len(set(letters_in_my_group)) != 1:
            return False

        # If the puzzle is incomplete, that's all we can check
        if any(c.free() for c in puzzle.state):
            return True

        # Else, there should be only one group that covers all my indices
        return len(my_groups) == 1

    def apply(self, puzzle):
        changed = False
        indices, letter = self.parameters["indices"], self.parameters["letter"]

        my_colors = [puzzle.state[idx].value for idx in indices if puzzle.state[idx].value != 0]
        my_color = my_colors[0] if my_colors else 0
        other_letters = [idx for c in puzzle.constraints if isinstance(c, LetterGroup) and c != self for idx in c.parameters["indices"]]
        neighbors_with_letters = [nei for idx in indices for nei in get_neighbors(puzzle.state, puzzle.width, puzzle.height, idx) if nei is not None and nei in other_letters]
        if my_color:
            # Apply opposite color to neighbors_with_letters
            my_opposite = [v for v in puzzle.domain if v != my_color][0]
            for nei in neighbors_with_letters:
                if puzzle.state[nei].value != my_opposite or puzzle.state[nei].options != []:
                    puzzle.state[nei].value = my_opposite
                    puzzle.state[nei].options = []
                    changed = True
            # Apply color to other members of the letter group
            for member in indices:
                if puzzle.state[member].value != my_color or puzzle.state[member].options != []:
                    puzzle.state[member].value = my_color
                    puzzle.state[member].options = []
                    changed = True
        return changed

    @staticmethod
    def generate_random_parameters(puzzle):
        # TODO allow reusing an existing letter but with some sort of poundering
        used_letters = [ord(c.parameters["letter"]) for c in puzzle.constraints if isinstance(c, LetterGroup)]
        if used_letters:
            max_letter = max(used_letters)
            letter = chr(max_letter + 1)
        else:
            letter = "A"
        used_indices = [idx for c in puzzle.constraints if isinstance(c, LetterGroup) for idx in c.parameters["indices"]]
        allowed_indices = [idx for idx in range(len(puzzle.state)) if idx
         not in used_indices]
        random.shuffle(allowed_indices)
        # TODO: sometimes we may want to add more indices
        indices = allowed_indices[:2]
        return {"indices": indices, "letter": letter}

    @staticmethod
    def maximum_presence(puzzle):
        return int((puzzle.width * puzzle.height) / 5)

    def line_export(self):
        indices, letter = self.parameters["indices"], self.parameters["letter"]
        indices = ".".join(str(i) for i in indices)
        return f"{self.slug}:{letter}.{indices}"

    @staticmethod
    def line_import(line):
        letter, indices = line.split(".", 1)
        indices = indices.split(".")
        indices = [int(idx) for idx in indices]
        return {"indices": indices, "letter": letter}

    def signature(self):
        letter = self.parameters["letter"]
        return f"{self.slug}:{letter}"
