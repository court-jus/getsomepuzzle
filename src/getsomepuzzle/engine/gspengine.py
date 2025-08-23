import time
import random
from .constraints import FixedValueConstraint
from .constraints.other_solution import OtherSolutionConstraint
from .constants import DOMAIN, MAX_STEPS, DEFAULT_SIZE
from .cell import Cell


class Puzzle:
    def __init__(self, *, running, width=DEFAULT_SIZE, height=DEFAULT_SIZE):
        self.running = running
        self.width = width
        self.height = height
        self.state = [Cell() for _ in range(width * height)]
        self.constraints = []

    def __repr__(self):
        result = [
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
        while steps > 0 and self.running.is_set():
            time.sleep(0.0001)
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
        while max_explorations > 0 and self.running.is_set():
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
        new_puzzle = Puzzle(running=self.running, width=self.width, height=self.height)
        new_puzzle.state = [c.clone() for c in self.state]
        new_puzzle.constraints = self.constraints
        return new_puzzle

