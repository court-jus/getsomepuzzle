#!/usr/bin/env python3

import random
from .constraints import (
    AllDifferentConstraint,
    FixedValueConstraint,
    AVAILABLE_RULES,
)
from .constraints.other_solution import OtherSolutionConstraint
from .constants import DOMAIN, MAX_STEPS, DEFAULT_SIZE
from .utils import state_to_str


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

    def small_repr(self):
        result = [
            f"Puzzle size is {self.width}x{self.height}",
            f"Possible values: {DOMAIN}",
        ]
        return "\n".join(result)

    def __repr__(self):
        # valid = self.is_valid()
        # poss = self.is_possible()
        result = [
            # ("V" if valid else "I") + ("P" if poss else "I") +
            # " - " + ".".join(map(str, self.state)),
            "Rules:",
            f"Puzzle size is {self.width}x{self.height}",
            f"Possible values: {DOMAIN}",
        ]
        for c in sorted(self.constraints):
            result.append(str(c))
        return "\n".join(result)

    def clear_solutions(self):
        self.constraints = [
            c for c in self.constraints if not isinstance(c, OtherSolutionConstraint)
        ]

    def is_valid(self, debug=False):
        if not self.is_possible():
            if debug:
                print("Not possible")
            return False
        for constraint in self.constraints:
            if not constraint.check(self):
                if debug:
                    print("Constraint", constraint, "is invalid")
                return False
        return True        

    def is_possible(self):
        return all(c.is_possible() for c in self.state)

    def is_complete(self, debug=False):
        return self.is_valid(debug=debug) and not self.free_cells()

    def free_cells(self):
        return [(c, idx) for idx, c in enumerate(self.state) if c.free()]

    def first_free_cell(self):
        cells = self.free_cells()
        if not cells:
            return None, None
        return cells[0]

    def add_constraint(self, new_constraint, debug=False):
        if debug:
            print("Trying to add", new_constraint, "to", [repr(c) for c in self.constraints])
        if any(c == new_constraint for c in self.constraints):
            raise ValueError("Cannot add rule, it's already there")
        if any(c.conflicts(new_constraint) for c in self.constraints):
            raise ValueError("Cannot add rule, it conflicts with another one")
        if isinstance(new_constraint, FixedValueConstraint):
            fixed_cells = [c for c in self.state if c.value]
            if len(fixed_cells) == (self.width * self.height) - 1:
                raise ValueError("Cannot add rule, it would fill the puzzle")
        self.constraints.append(new_constraint)
        if debug:
            print("Good it's added")
        self.apply_fixed_constraints(debug=debug)
            

    def apply_fixed_constraints(self, debug=False):
        for constraint in self.constraints:
            if isinstance(constraint, FixedValueConstraint):
                if debug:
                    print("Apply", constraint)
                idx, val = constraint.parameters["idx"], constraint.parameters["val"]
                self.state[idx].value = val
                self.state[idx].options = []
        if debug:
            print("fixed values are now", [c.value for c in self.state])
        self.constraints = [
            c for c in self.constraints if not isinstance(c, FixedValueConstraint)
        ]

    def reset_user_input(self):
        for cell in self.state:
            if cell.value != 0 and cell.options:
                cell.value = 0

    def simplify(self, solution, debug=False):
        # Pick a value from the solution
        cell, idx = random.choice(self.free_cells())
        cell.value = solution.state[idx].value
        cell.options = []
        if debug:
            print("Simplify: Set cell", idx, "to", cell.value)

    def remove_useless_rules(self, debug=False):
        solutions = self.find_solutions()
        if debug:
            print(f"Initially, we have {len(solutions)} solution:")
            for sol in solutions:
                print("SOLUTION", sol)
        initial_solutions = len(solutions)
        initial_constraints = self.constraints[:]
        removed = []
        for idx, constraint in enumerate(self.constraints):
            if debug:
                print("Will try to remove constraint", idx, constraint)
            new_puzzle = self.clone()
            new_puzzle.constraints = [
                c for i, c in enumerate(self.constraints)
                if i not in removed and i != idx
            ]
            solutions = new_puzzle.find_solutions()
            if solutions and len(solutions) == initial_solutions:
                if debug:
                    print("Still valid, move on")
                removed.append(idx)
            else:
                if debug:
                    print("Nope, we'll keep that one")
        if removed:
            self.constraints = [
                c for i, c in enumerate(self.constraints)
                if i not in removed
            ]
            if debug:
                print("We removed", removed)
        else:
            if debug:
                print("Nothing can be removed")
        self.remove_useless_fixed_values(initial_solutions, debug=debug)

    def remove_useless_fixed_values(self, initial_solutions, debug=False):
        # Now try to remove some fixed values
        initial_values = {
            idx: cell.value
            for idx, cell in enumerate(self.state)
            if cell.value != 0
        }
        if debug:
            print("Initial values", initial_values)
        removed = []
        for idx, cell in enumerate(self.state):
            if debug:
                print(f"Will try to remove {idx+1}={cell.value}")
            new_puzzle = self.clone()
            for i, c in enumerate(new_puzzle.state):
                if i in removed or i == idx:
                    c.value = 0
                    c.options = DOMAIN[:]
            solutions = new_puzzle.find_solutions()
            if solutions and len(solutions) == initial_solutions:
                if debug:
                    print("Still valid, move on")
                removed.append(idx)
            else:
                if debug:
                    print("Nope, we'll keep that one")
        if removed:
            for i, c in enumerate(self.state):
                if i in removed or i == idx:
                    c.value = 0
                    c.options = DOMAIN[:]
            if debug:
                print("We removed", removed)
        else:
            if debug:
                print("Nothing can be removed")

    def find_solution(self, starting_state, debug=False):
        st = starting_state.clone()
        log_history = []
        steps = MAX_STEPS
        backpropagations = 0
        while steps > 0:
            if st.is_complete():
                break
            if debug:
                print(st.state)
            steps -= 1
            cell, idx = st.first_free_cell()
            if cell is None or not st.is_possible():
                if debug:
                    print("Not possible anymore")
                    print("HISTORY:")
                    print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
                # Rewind history, until we find a moment where a value was fixed,
                # change that value and keep looking for solutions.
                if not log_history:
                    if debug:
                        print("No history left, no solution found")
                    return None, None
                previous_line = st
                v = 0
                backpropagations += 1
                for hidx, line in enumerate(log_history[::-1]):
                    cell_idx, chosen_value, options_remaining = line
                    if debug:
                        print(f"We had chosen {cell_idx+1} = {chosen_value} and still had options {options_remaining}")
                    if not options_remaining:
                        continue
                    if debug:
                        print("We could have chosen another option, let's try it")
                    break
                else:
                    if debug:
                        print("Found nothing changeable in history")
                    return None, None
                if debug:
                    print(f"Found changeable history: {cell_idx + 1} = {chosen_value} ({options_remaining})")
                st = starting_state.clone()
                if debug:
                    print("Replaying history until that moment")
                new_history = []
                for hidx, (h_cidx, h_value, h_options) in enumerate(log_history[:-hidx-1]):
                    if debug:
                        print(f"H{hidx} : {h_cidx + 1} = {h_value}")
                    st.state[h_cidx].value = h_value
                    st.state[h_cidx].options = h_options[:]
                    new_history.append([h_cidx, h_value, h_options])
                if debug:
                    print(f"Now we make a new choice for {cell_idx + 1}")
                cell = st.state[cell_idx]
                cell.value = options_remaining[0]
                cell.options = [o for o in options_remaining if o != cell.value]
                new_history.append([cell_idx, cell.value, cell.options])
                log_history = new_history
                if debug:
                    print("NEW HISTORY:")
                    print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
            elif cell is not None and cell.options:
                new_value = cell.options[0]
                cell.value = new_value
                if debug:
                    print("try with", idx + 1, "=", cell.value)
                    print("so now we have")
                    print(st.state)
                if st.is_valid(debug=debug):
                    if debug:
                        print("that's valid")
                    log_history.append([idx, new_value, [o for o in cell.options if o != new_value]])
                    if debug:
                        print("HISTORY NOW:")
                        print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
                    continue
                if debug:
                    print("invalid, remove this value and set back to 0")
                st = st.clone()
                st.state[idx].options = [
                    o for o in st.state[idx].options if o != new_value
                ]
                st.state[idx].value = 0
                if debug:
                    print("so now we are back with")
                    print(st.state)
        if not steps:
            raise RuntimeError("Reached MAX_STEPS")

        if not st.is_complete():
            return None, None
        return st, backpropagations

    def find_solutions(self, max_solutions=2, debug=False):
        initial_state = self.clone()
        initial_state.apply_fixed_constraints(debug=debug)
        max_explorations = max_solutions
        while max_explorations > 0:
            max_explorations -= 1
            try:
                solution, _ = self.find_solution(initial_state, debug=debug)
            except RuntimeError:
                break                
            if debug:
                print("* Found solution", solution.state if solution is not None else None)
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

    def check_solution(self, solution, debug=False):
        if debug:
            print("Check solution", solution)
        puzzle = self.clone()
        for idx, val in enumerate(solution):
            puzzle.state[idx].value = val
            puzzle.state[idx].options = []
        if puzzle.is_complete():
            return True
        if debug:
            for constraint in puzzle.constraints:
                print("Check constraint", constraint)
                print("->", constraint.check(puzzle))
        return False

    def clone(self):
        new_puzzle = Puzzle(width=self.width, height=self.height)
        new_puzzle.state = [c.clone() for c in self.state]
        new_puzzle.constraints = self.constraints
        return new_puzzle


class PuzzleGenerator:
    def __init__(self, width=DEFAULT_SIZE, height=DEFAULT_SIZE, callback=None):
        # History of the constraints added
        self.puzzle = Puzzle(width, height)
        self.callback = callback if callback is not None else lambda x:x

    def add_random_rule(self, banned_constraints, debug=False):
        max_iter = 1000
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
                    if debug:
                        print("Cannot add", new_constraint, "it is banned")
                    continue
                presence = len(
                    list(c for c in self.puzzle.constraints if isinstance(c, rule))
                )
                if hasattr(
                    rule, "maximum_presence"
                ) and presence >= rule.maximum_presence(self.puzzle):
                    if debug:
                        print("Cannot add", new_constraint, "it's already too much present")
                    continue
                self.puzzle.add_constraint(new_constraint, debug=debug)
            except ValueError as err:
                if debug:
                    print("Cannot add", new_constraint, err)
                # The puzzle already has this constraint or there is a conflict
                continue
            else:
                # print("Added", new_constraint)
                return new_constraint
        raise RuntimeError("Max iter reach to add random rule")

    def remove_last_rule(self):
        removed_constraint = self.puzzle.constraints[-1]
        # print("Remove", removed_constraint)
        self.puzzle.constraints = self.puzzle.constraints[:-1]
        return removed_constraint

    def generate(self, *forced_constraints, debug=False):
        self.callback(3)
        for forced_constraint in forced_constraints:
            self.puzzle.add_constraint(forced_constraint, debug=debug)
        max_number_fixed = int(self.puzzle.width * self.puzzle.height * 0.4)
        number_fixed = random.randint(3, max_number_fixed)
        while number_fixed > 0:
            try:
                parameters = FixedValueConstraint.generate_random_parameters(self.puzzle)
                self.puzzle.add_constraint(FixedValueConstraint(**parameters), debug=debug)
            except RuntimeError:
                pass
            else:
                number_fixed -= 1
        self.puzzle.apply_fixed_constraints(debug=debug)
        self.callback(4)
        previous_version = self.puzzle.clone()
        has_solution = True
        banned_constraints = []
        progress = 5
        while has_solution:
            self.callback(progress)
            progress += 1
            try:
                self.add_random_rule(banned_constraints, debug=debug)
            except RuntimeError:
                return None

            # Find solution
            solutions = self.puzzle.find_solutions(debug=debug)
            if debug:
                print(" Found", len(solutions), "solutions")
            has_solution = bool(solutions)
            if not solutions:
                # Remove last constraint
                progress -= 1
                self.callback(progress)
                banned_constraints.append(self.remove_last_rule())
                has_solution = True
                continue
            self.puzzle.clear_solutions()
            if len(solutions) == 1:
                self.callback(100)
                return self.puzzle
            previous_version = self.puzzle.clone()
            previous_version.clear_solutions()
        return None


def main():
    # print("=" * 80)
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
    # print(". . .", bp, ". . .")
    # print(pu)
    print(state_to_str(pu))
    # print("-" * 80)
    c = False
    failures = 0
    while not c:
        solution = input("Your solution (empty to cancel):").strip()
        # print("you typed", solution)
        if not solution:
            return
        solution = [int(c) for c in solution]
        # print(solution)
        c = pu.check_solution(solution)
        if c:
            # print("You win")
            return
        # print("Try again", failures)
        failures += 1
        if failures > 5:
            print("Solutions:")
            for sol in pu.find_solutions():
                print(sol)


if __name__ == "__main__":
    main()
