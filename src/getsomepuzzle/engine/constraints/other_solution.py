import random

from .base import Constraint


class OtherSolutionConstraint(Constraint):

    def check(self, puzzle, debug=False):
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
