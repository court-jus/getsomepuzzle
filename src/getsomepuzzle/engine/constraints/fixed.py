import random

from .base import Constraint
from ..constants import EMPTY
from ..errors import CannotApplyConstraint


class FixedValueConstraint(Constraint):
    slug = "FX"

    def __repr__(self):
        idx, val = self.parameters["idx"], self.parameters["val"]
        return f"Cell {idx + 1} should equal {val}"

    def check(self, puzzle, debug=False):
        idx, val = self.parameters["idx"], self.parameters["val"]
        return puzzle.state[idx].value == val or val in puzzle.state[idx].options

    def apply(self, puzzle):
        idx, val = self.parameters["idx"], self.parameters["val"]
        if puzzle.state[idx].value != val and puzzle.state[idx].value != EMPTY:
            raise CannotApplyConstraint
        return puzzle.state[idx].set_value(val)

    @staticmethod
    def generate_random_parameters(puzzle):
        return {
            "idx": random.randint(0, len(puzzle.state) - 1),
            "val": random.choice(puzzle.domain),
        }

    def conflicts(self, other):
        if not isinstance(other, FixedValueConstraint):
            return False
        return other.parameters["idx"] == self.parameters["idx"]

    def line_export(self):
        idx, val = self.parameters["idx"], self.parameters["val"]
        return f"{self.slug}:{idx}.{val}"

    @staticmethod
    def line_import(line):
        idx, val = line.split(".")
        return {"idx": int(idx), "val": int(val)}
