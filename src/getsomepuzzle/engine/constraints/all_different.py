from ..utils import to_rows, to_columns
from .base import Constraint
from ..constants import EMPTY


class AllDifferentConstraint(Constraint):
    slug = "AD"

    def __repr__(self):
        return "All cells must contain different values (per row and column)"

    def check(self, puzzle, debug=False):
        # All values should be different
        w, h = puzzle.width, puzzle.height
        rows = to_rows(puzzle.state, w, h)
        columns = to_columns(puzzle.state, w)
        for zone in rows + columns:
            zone_values = [c.value for c in zone if c.value != EMPTY]
            if len(zone_values) != len(set(zone_values)):
                return False
        return True

    @staticmethod
    def maximum_presence(*_a):
        return 1

    def line_export(self):
        return self.slug

    @staticmethod
    def line_import(line):
        return {}
