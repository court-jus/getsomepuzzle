import random

from .base import Constraint
from ..constants import DOMAIN


class FixedValueConstraint(Constraint):
    def __repr__(self):
        idx, val = self.parameters["idx"], self.parameters["val"]
        return f"Cell {idx + 1} should equal {val}"

    def check(self, puzzle, debug=False):
        idx, val = self.parameters["idx"], self.parameters["val"]
        return puzzle.state[idx].value == val or val in puzzle.state[idx].options

    @staticmethod
    def generate_random_parameters(puzzle):
        return {
            "idx": random.randint(0, len(puzzle.state) - 1),
            "val": random.choice(DOMAIN),
        }

    def conflicts(self, other):
        if not isinstance(other, FixedValueConstraint):
            return False
        return other.parameters["idx"] == self.parameters["idx"]
