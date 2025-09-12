import random
import re

from ..utils import to_grid, to_groups
from .base import Constraint


class QuantityAllConstraint(Constraint):
    slug = "QA"

    def __repr__(self):
        value, count = self.parameters["value"], self.parameters["count"]
        return f"The total number of {value} should be {count}"

    def conflicts(self, other):
        # Can't have two QA constraints
        return isinstance(other, QuantityAllConstraint)

    def check(self, puzzle, debug=False):
        result = self._check(puzzle, debug=debug)
        if self.ui_widget is not None:
            self.ui_widget.color = "green" if result else "red"
        return result

    def _check(self, puzzle, debug=False):
        # If any of the cells are not filled yet, there's no need to check further
        if any(c.free() for c in puzzle.state):
            return True

        value, count = self.parameters["value"], self.parameters["count"]
        matching_cells = [1 for c in puzzle.state if c.value == value]
        return len(matching_cells) == count

    @staticmethod
    def generate_random_parameters(puzzle):
        min_count = 1
        max_count = (puzzle.width * puzzle.height) - 1
        return {
            "count": random.randint(min_count, max_count),
            "value": random.choice(puzzle.domain),
        }

    @staticmethod
    def maximum_presence(puzzle):
        return len(puzzle.domain)

    def line_export(self):
        value, count = self.parameters["value"], self.parameters["count"]
        return f"{self.slug}:{value}.{count}"

    @staticmethod
    def line_import(line):
        value, count = line.split(".")
        return {"value": int(value), "conut": int(count)}
