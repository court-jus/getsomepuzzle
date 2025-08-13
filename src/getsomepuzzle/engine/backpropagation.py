#!/usr/bin/env python3

import random
from .constraints import (
    AllDifferentConstraint,
    FixedValueConstraint,
    OtherSolutionConstraint,
    AVAILABLE_RULES,
)
from .constants import DOMAIN, MAX_STEPS, DEFAULT_SIZE
from .utils import show_solution


class Cell:
    def __init__(self):
        self.options = DOMAIN[:]
        self.value = 0

    def __repr__(self):
        symb = " " if self.value else "_"
        return "".join(
            map(
                str,
                [
                    (
                        v
                        if (v == self.value or (not self.value and v in self.options))
                        else symb
                    )
                    for v in DOMAIN
                ],
            )
        )

    def free(self):
        return not self.value and self.options

    def is_possible(self):
        return self.value or self.options

    def clone(self):
        c = Cell()
        c.value = self.value
        c.options = self.options[:]
        return c


class Puzzle:
    def __init__(self, width=DEFAULT_SIZE, height=DEFAULT_SIZE):
        self.width = width
        self.height = height
        self.state = [Cell() for _ in range(width * height)]
        self.constraints = []

    def __repr__(self):
        # valid = self.is_valid()
        # poss = self.is_possible()
        result = [
            # ("V" if valid else "I") + ("P" if poss else "I") +
            # " - " + ".".join(map(str, self.state)),
            "Rules:",
            f"Puzzle size is {len(self.state)}",
            f"Possible values: {DOMAIN}",
        ]
        for c in sorted(self.constraints):
            result.append(str(c))
        return "\n".join(result)

    def clear_solutions(self):
        self.constraints = [
            c for c in self.constraints if not isinstance(c, OtherSolutionConstraint)
        ]

    def is_valid(self):
        if not self.is_possible():
            return False
        return all(constraint.check(self) for constraint in self.constraints)

    def is_possible(self):
        return all(c.is_possible() for c in self.state)

    def is_complete(self):
        return self.is_valid() and not self.free_cells()

    def free_cells(self):
        return [(c, idx) for idx, c in enumerate(self.state) if c.free()]

    def first_free_cell(self):
        cells = self.free_cells()
        if not cells:
            return None, None
        return cells[0]

    def add_constraint(self, new_constraint):
        # print("Trying to add", new_constraint, "to", [repr(c) for c in self.constraints])
        if any(c == new_constraint for c in self.constraints):
            raise ValueError("Cannot add rule, it's already there")
        if any(c.conflicts(new_constraint) for c in self.constraints):
            raise ValueError("Cannot add rule, it conflicts with another one")
        self.constraints.append(new_constraint)

    def apply_fixed_constraints(self):
        for constraint in self.constraints:
            if isinstance(constraint, FixedValueConstraint):
                print("Apply", constraint)
                idx, val = constraint.parameters["idx"], constraint.parameters["val"]
                self.state[idx].value = val
                self.state[idx].options = []
        self.constraints = [
            c for c in self.constraints if not isinstance(c, FixedValueConstraint)
        ]

    def simplify(self, solution):
        # Pick a value from the solution
        cell, idx = random.choice(self.free_cells())
        cell.value = solution.state[idx].value
        cell.options = []
        # print("Set cell", idx, "to", cell.value)

    def find_solution(self, starting_state):
        st = starting_state.clone()
        history = [st.clone()]
        steps = MAX_STEPS
        backpropagations = 0
        while steps > 0:
            if st.is_complete():
                break
            steps -= 1
            cell, idx = st.first_free_cell()
            if cell is None or not st.is_possible():
                # Rewind history, until we find a moment where a value was fixed,
                # change that value and keep looking for solutions.
                if not history:
                    return None, None
                previous_line = st
                new_history = []
                v = 0
                backpropagations += 1
                for hidx, line in enumerate(history[::-1]):
                    previous_choices = [
                        c.value for c in previous_line.state if c.value != 0
                    ]
                    current_choices = [c.value for c in line.state if c.value != 0]
                    if len(previous_choices) == len(current_choices):
                        previous_line = line
                        new_history.append(line)
                        continue
                    # Find the index and changed value
                    for idx, v in enumerate(previous_choices):
                        if idx >= len(current_choices) or current_choices[idx] != v:
                            break
                    else:
                        # If we are back at the start of history, it means we explored everything
                        # and the puzzle is impossible.
                        return None, None
                    break
                if not v:
                    return None, None
                st = previous_line.clone()
                cell = st.state[idx]
                cell.value = 0
                if v not in cell.options:
                    return None, None
                cell.options.remove(v)
                history = history[:-hidx]
            if cell is not None and cell.options:
                new_value = cell.options[0]
                cell.value = new_value
                if st.is_valid():
                    history.append(st.clone())
                    continue
                st = st.clone()
                st.state[idx].options = [
                    o for o in st.state[idx].options if o != new_value
                ]
                st.state[idx].value = 0
        if not steps:
            raise RuntimeError("Reached MAX_STEPS")

        if not st.is_complete():
            return None, None
        return st, backpropagations

    def find_solutions(self, max_solutions=2):
        initial_state = self.clone()
        initial_state.apply_fixed_constraints()
        max_explorations = max_solutions
        while max_explorations > 0:
            max_explorations -= 1
            solution, _ = self.find_solution(initial_state)
            if solution is None:
                break

            # Forbid this solution
            found_solution = [c.value for c in solution.state]
            initial_state.constraints.append(
                OtherSolutionConstraint(solution=found_solution)
            )

        solutions = []
        for constraint in initial_state.constraints:
            if isinstance(constraint, OtherSolutionConstraint):
                solutions.append(constraint.parameters["solution"])
        return solutions

    def check_solution(self, solution):
        puzzle = self.clone()
        for idx, val in enumerate(solution):
            puzzle.state[idx].value = val
            puzzle.state[idx].options = []
        if puzzle.is_complete():
            return True
        for constraint in puzzle.constraints:
            if not constraint.check(puzzle):
                print("Check failed for", constraint)
        return False

    def clone(self):
        new_puzzle = Puzzle()
        new_puzzle.state = [c.clone() for c in self.state]
        new_puzzle.constraints = self.constraints
        return new_puzzle


class PuzzleGenerator:
    def __init__(self, size=DEFAULT_SIZE):
        # History of the constraints added
        self.history = []
        self.puzzle = Puzzle(size, size)

    def add_random_rule(self, banned_constraints):
        max_iter = 100
        while max_iter > 0:
            max_iter -= 1
            rule = random.choice(AVAILABLE_RULES)
            parameters = {}
            if hasattr(rule, "generate_random_parameters"):
                try:
                    parameters = rule.generate_random_parameters(self.puzzle)
                except ValueError:
                    continue
            try:
                new_constraint = rule(**parameters)
                if any(c == new_constraint for c in banned_constraints):
                    # print("Cannot add", new_constraint, "it is banned")
                    continue
                presence = len(
                    list(c for c in self.puzzle.constraints if isinstance(c, rule))
                )
                if hasattr(
                    rule, "maximum_presence"
                ) and presence >= rule.maximum_presence(self.puzzle):
                    # print("Cannot add", new_constraint, "it's already too much present")
                    continue
                self.puzzle.add_constraint(new_constraint)
            except ValueError:
                # The puzzle already has this constraint or there is a conflict
                continue
            else:
                # print("Add", new_constraint)
                return new_constraint
        raise RuntimeError("Max iter reach to add random rule")

    def remove_last_rule(self):
        removed_constraint = self.puzzle.constraints[-1]
        # print("Remove", removed_constraint)
        self.puzzle.constraints = self.puzzle.constraints[:-1]
        return removed_constraint

    def generate(self, *forced_constraints):
        for forced_constraint in forced_constraints:
            self.puzzle.add_constraint(forced_constraint)
        previous_version = self.puzzle.clone()
        has_solution = True
        banned_constraints = []
        while has_solution:
            self.add_random_rule(banned_constraints)

            # Find solution
            solutions = self.puzzle.find_solutions()
            # print(" Found", len(solutions), "solutions")
            has_solution = bool(solutions)
            if not solutions:
                # Remove last constraint
                banned_constraints.append(self.remove_last_rule())
                has_solution = True
                continue
            self.puzzle.clear_solutions()
            if len(solutions) == 1:
                return self.puzzle
            previous_version = self.puzzle.clone()
            previous_version.clear_solutions()
        return None


def main():
    print("=" * 80)
    size = 5
    puzzle_generated = False
    while not puzzle_generated:
        try:
            pg = PuzzleGenerator(size)
            pu = pg.generate(AllDifferentConstraint())
        except RuntimeError:
            continue
        else:
            puzzle_generated = True
    pu.clear_solutions()
    pu.apply_fixed_constraints()
    solution, bp = pu.find_solution(pu)
    max_simplifications = 30
    while bp > 1 and max_simplifications > 0:
        max_simplifications -= 1
        pu.simplify(solution)
        solution, bp = pu.find_solution(pu)
    print(". . .", bp, ". . .")
    print(pu)
    show_solution(pu)
    print("-" * 80)
    c = False
    failures = 0
    while not c:
        solution = input("Your solution (empty to cancel):").strip()
        print("you typed", solution)
        if not solution:
            return
        solution = [int(c) for c in solution]
        print(solution)
        c = pu.check_solution(solution)
        if c:
            print("You win")
            return
        print("Try again", failures)
        failures += 1
        if failures > 5:
            print("Solutions:")
            for sol in pu.find_solutions():
                print(sol)


if __name__ == "__main__":
    main()
