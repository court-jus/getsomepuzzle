import re
import functools
import random
from .utils import to_rows, to_columns, to_grid
from .constants import DOMAIN


@functools.total_ordering
class Constraint:
    def __init__(self, **parameters):
        self.parameters = parameters

    def __repr__(self):
        return f"{self.__class__.__name__}({self.parameters})"

    def __eq__(self, other):
        # Two constraints are identical if they are of the same class
        # and the same parameters
        return type(self) == type(other) and self.parameters == other.parameters

    def __lt__(self, other):
        if type(self) != type(other):
            return type(self).__name__ < type(other).__name__
        if (
            "idx" in self.parameters
            and "idx" in other.parameters
            and self.parameters["idx"] != other.parameters["idx"]
        ):
            return self.parameters["idx"] < other.parameters["idx"]
        if (
            "val" in self.parameters
            and "val" in other.parameters
            and self.parameters["val"] != other.parameters["val"]
        ):
            return self.parameters["val"] < other.parameters["val"]
        return True

    def conflicts(self, _other):
        return False

    def check(self, puzzle):
        raise NotImplementedError("Should be implemented by subclass")


class OtherSolutionConstraint(Constraint):

    def check(self, puzzle):
        # The final solution should NOT be the one given
        values = [c.value for c in puzzle.state]
        if any(v == 0 for v in values):
            return True
        return not all(a == b for a, b in zip(values, self.parameters["solution"]))

    @staticmethod
    def generate_random_parameters(puzzle):
        max_tries = 20
        board_solutions = [
            c.parameters["solution"]
            for c in puzzle.constraints
            if isinstance(c, OtherSolutionConstraint)
        ]
        while max_tries > 0:
            max_tries -= 1
            solution = [i + 1 for i in range(len(puzzle.state))]
            random.shuffle(solution)
            if solution not in board_solutions:
                return {"solution": solution}
        raise ValueError("Cannot generate parameters")


class AllDifferentConstraint(Constraint):

    def __repr__(self):
        return "All cells must contain different values (per row and column)"

    def check(self, puzzle):
        # All values should be different
        w, h = puzzle.width, puzzle.height
        rows = to_rows(puzzle.state, w, h)
        columns = to_columns(puzzle.state, w)
        for zone in rows + columns:
            zone_values = [c.value for c in zone if c.value != 0]
            if len(zone_values) != len(set(zone_values)):
                return False
        return True

    @staticmethod
    def maximum_presence(*_a):
        return 1


class ForbiddenMotif(Constraint):
    def __repr__(self):
        motif = self.parameters["motif"]
        return f"Motif {motif} is forbidden"

    def check(self, puzzle):
        motif = self.parameters["motif"]
        grid = to_grid(
            puzzle.state, puzzle.width, puzzle.height, lambda cell: int(cell.value)
        )
        rows = ["".join(map(str, row)) for row in grid]
        findings = {}
        for midx, motifline in enumerate(motif):
            for ridx, row in enumerate(rows):
                matches = [
                    m.start()
                    for m in re.finditer(motifline, row)
                    if midx == 0
                    or m.start() in findings.get(midx - 1, {}).get(ridx - 1, [])
                ]
                if matches:
                    if midx == len(motif) - 1:
                        return False
                    findings.setdefault(midx, {})[ridx] = matches

        return True

    @staticmethod
    def generate_random_parameters(puzzle):
        motifw = random.randint(1, min(3, puzzle.width))
        motifh = random.randint(1 if motifw > 1 else 2, min(3, puzzle.height))
        motif = [
            "".join([str(random.choice(DOMAIN)) for i in range(motifw)])
            for j in range(motifh)
        ]
        return {"motif": motif}

    def conflicts(self, other):
        if type(self) != type(other):
            return False

        smotif, omotif = self.parameters["motif"], other.parameters["motif"]
        if len(smotif) == len(omotif):
            return omotif == smotif
        if len(smotif) > len(omotif):
            return omotif in smotif
        return smotif in omotif

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width


class ParityConstraint(Constraint):
    def __repr__(self):
        idx, side = self.parameters["idx"], self.parameters["side"]
        return (
            f"Cell {idx + 1} should have the same number "
            f"of odd and even numbers on its {side} "
            f"side{'s' if side == 'both' else ''}"
        )

    def check(self, puzzle):
        # The given cell has the same number of odd and even numbers on
        # one of its side (or both), the given cell and side are defined
        # in the parameters
        idx, side = self.parameters["idx"], self.parameters["side"]
        print("will check", idx, side)
        w, h = puzzle.width, puzzle.height
        rows = to_rows(puzzle.state, w, h)
        for row in rows:
            # FIXME: it does not work at all for rows > 1
            # print("ROW", row)
            values_and_indices = [(idx, c.value) for idx, c in enumerate(row)]
            # print("VAI", values_and_indices)
            sides = []
            if side in ("left", "both"):
                sides.append([v for (i, v) in values_and_indices if i < idx])
            if side in ("right", "both"):
                sides.append([v for (i, v) in values_and_indices if i > idx])
            for side in sides:
                # print("SIDE", side)
                if any(v == 0 for v in side):
                    continue
                even = len([v for v in side if v % 2 == 0])
                odd = len([v for v in side if v % 2 != 0])
                # print(even, odd)
                if even != odd:
                    return False
        return True

    def conflicts(self, other):
        if type(other) != type(self):
            return False
        return self.parameters["idx"] == other.parameters["idx"]

    @staticmethod
    def generate_random_parameters(puzzle):
        # { "idx" : 4, "side" : "left" or "both" or "right" }
        choices = ["left", "right"]
        size = puzzle.width
        if size % 2 != 0:
            choices.append("both")
        side = random.choice(choices)
        min_left = 2 if side in ("left", "both") else 0
        max_right = size - 2 if side in ("right", "both") else size
        # the side(s) we pick must have an even number of cells
        # so, because we are zero indexed, the index must be even
        possible_indices = [
            i for i in range(size) if min_left <= i <= max_right and i % 2 == 0
        ]
        if not possible_indices:
            raise ValueError("Cannot generate parity constraint")
        col = random.choice(possible_indices)
        row = random.randint(0, puzzle.height - 1)
        return {"idx": col + row * puzzle.width, "side": side}

    @staticmethod
    def maximum_presence(puzzle):
        return puzzle.width


class FixedValueConstraint(Constraint):
    def __repr__(self):
        idx, val = self.parameters["idx"], self.parameters["val"]
        return f"Cell {idx + 1} should equal {val}"

    def check(self, puzzle):
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


AVAILABLE_RULES = [
    AllDifferentConstraint,
    FixedValueConstraint,
    ParityConstraint,
    ForbiddenMotif,
]
