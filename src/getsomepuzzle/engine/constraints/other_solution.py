import random

from ..constants import EMPTY
from .base import Constraint


class OtherSolutionConstraint(Constraint):
    slug = "OS"

    def check(self, puzzle, debug=False):
        # The final solution should NOT be the one given
        values = [c.value for c in puzzle.state]
        if any(v == EMPTY for v in values):
            return True
        return not all(a == b for a, b in zip(values, self.parameters["solution"]))

    def apply(self, puzzle):
        return False

    def line_export(self):
        sol = "".join(str(v) for v in self.parameters["solution"])
        return f"{self.slug}:{sol}"
