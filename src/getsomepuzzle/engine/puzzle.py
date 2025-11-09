import random
from .constraints import FixedValueConstraint
from .constraints.base import CellCentricConstraint
from .constants import DOMAIN, DEFAULT_SIZE, EMPTY, MAX_FORCABLE
from .errors import RuleConflictError, CannotApplyConstraint
from .cell import Cell
from .solver.puzzle_solver import find_solution, find_solutions
from .utils import line_export

class Puzzle:
    def __init__(self, *, running, width=DEFAULT_SIZE, height=DEFAULT_SIZE, domain=None):
        self.running = running
        self.width = width
        self.height = height
        self.domain = domain if domain is not None else DOMAIN
        self.state = [Cell(self.domain) for _ in range(width * height)]
        self.constraints = []

    def __repr__(self):
        result = [
            "Rules:",
            f"Puzzle size is {self.width}x{self.height}",
            f"Possible values: {self.domain}",
        ]
        for c in sorted(self.constraints):
            result.append(str(c))
        return "\n".join(result)

    def set_value(self, idx, value):
        return self.state[idx].set_value(value)

    def get_cell_constraint(self, idx):
        for c in self.constraints:
            if isinstance(c, CellCentricConstraint) and c.parameters["idx"] == idx:
                return { "constraint": c, "text": c.get_cell_text() }
        return None

    def clear_solutions(self):
        self.constraints = [c for c in self.constraints if c.slug != "OS"]

    def is_valid(self, debug=False):
        if not self.is_possible():
            if debug:
                print("Not possible")
            return False
        for constraint in self.constraints:
            if not constraint.check(self, debug=debug):
                if debug:
                    print("Constraint", constraint, "is invalid")
                return False
        return True        

    def is_possible(self):
        return all(c.is_possible() for c in self.state)

    def is_complete(self, debug=False):
        return self.is_valid(debug=debug) and not self.free_cells()

    def is_forcable(self):
        # We consider that if we have 16 or less empty cells, we can
        # brute force the puzzle
        return len(self.free_cells()) <= MAX_FORCABLE

    def free_cells(self):
        return [(c, idx) for idx, c in enumerate(self.state) if c.free()]

    def compute_ratio(self):
        values = [c.value for c in self.state]
        return values.count(EMPTY) / len(values)

    def first_free_cell(self):
        cells = self.free_cells()
        if not cells:
            return None, None
        return cells[0]

    def add_constraint(self, new_constraint, debug=False, auto_apply=True, auto_check=True):
        if debug:
            print("Trying to add", new_constraint, "to", [repr(c) for c in self.constraints])
        if any(c == new_constraint for c in self.constraints):
            raise RuleConflictError("Cannot add rule, it's already there")
        if isinstance(new_constraint, FixedValueConstraint):
            if new_constraint.parameters["val"] not in self.state[new_constraint.parameters["idx"]].options:
                raise RuleConflictError(f"Cannot add rule, it conflicts with current state")
        conflicting = [c for c in self.constraints if c.conflicts(new_constraint)]
        if conflicting:
            raise RuleConflictError(f"Cannot add rule, it conflicts with {conflicting}")
        if isinstance(new_constraint, FixedValueConstraint):
            fixed_cells = [c for c in self.state if c.value]
            if len(fixed_cells) == (self.width * self.height) - 1:
                raise RuleConflictError("Cannot add rule, it would fill the puzzle")
        if auto_check:
            # Try to solve
            tmp = self.clone()
            tmp.constraints.append(new_constraint)
            sol, bp, _ = find_solution(self.running, tmp, debug=debug)
            if not sol:
                raise RuleConflictError("Cannot add rule, it makes the puzzle unsolvable")
        self.constraints.append(new_constraint)
        if debug:
            print("Good it's added, let's apply it")
        if auto_apply:
            self.apply_constraints()

        # if isinstance(new_constraint, FixedValueConstraint):
        #     self.apply_fixed_constraints(debug=debug)
            
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

    def apply_constraints(self, auto_check=False, explain=False, only_idx=None):
        changed = True
        globally_changed = False
        while changed:
            changed = False
            for constraint in self.constraints:
                if explain:
                    print("  What does", constraint, "say?")
                if only_idx is not None and only_idx not in constraint.influence(self):
                    continue
                before = [c.value for c in self.state]
                if constraint.apply(self):
                    if explain:
                        diff = "".join(str(c.value) if before[idx] == EMPTY and c.value != EMPTY else "." for idx, c in enumerate(self.state))
                        print("  Constraint", constraint, "gives us:")
                        print(" ", diff)
                    changed = True
                    break
                elif explain:
                    print("  Constraint", constraint, "has nothing (more) to say")
            globally_changed |= changed
        if auto_check:
            if not all(c.check(self) for c in self.constraints):
                failed = [c for c in self.constraints if not c.check(self)]
                raise CannotApplyConstraint(str(failed))
        return globally_changed

    def apply_with_force(self, explain=False):
        # Iterate over free cells. For each cell, try both values
        # and apply constraints each time
        changed = False
        cells = self.free_cells()
        for cell, idx in cells:
            if len(cell.options) <= 1:
                continue
            for value in cell.options:
                if explain:
                    print(f"Set {idx + 1} to {value}")
                test_pu = self.clone()
                test_pu.set_value(idx, value)
                try:
                    test_pu.apply_constraints(auto_check=True, explain=explain, only_idx=idx)
                except CannotApplyConstraint as exc:
                    if explain:
                        print(" ", exc, f"tells us that cell {idx + 1} cannot equal {value}")
                    # Remove this options from cell
                    cell.options.remove(value)
                    if len(cell.options) == 1:
                        if explain:
                            print(f"  So we set {idx + 1} to {cell.options[0]}")
                        cell.set_value(cell.options[0])
                        changed = True
                    elif len(cell.options) == 0:
                        if explain:
                            print("  But now it has no option, that's a problem")
                        raise
                else:
                    if explain:
                        print(f"  It's OK to have {idx + 1} = {value}")
        return changed

    def reset_user_input(self):
        for cell in self.state:
            if cell.value != EMPTY and cell.options:
                cell.value = EMPTY

    def simplify(self, solution, debug=False):
        # Pick a value from the solution
        cell, idx = random.choice(self.free_cells())
        cell.value = solution.state[idx].value
        cell.options = []
        if debug:
            print("Simplify: Set cell", idx, "to", cell.value)

    def remove_useless_rules(self, debug=False):
        solutions = find_solutions(self, self.running, debug=False)
        if debug:
            print(f"Initially, we have {len(solutions)} solution:")
            for sol in solutions:
                print("SOLUTION", sol)
        initial_solutions = len(solutions)
        removed = []
        for _ in range(len(self.constraints)):
            constraint = self.constraints.pop()
            if debug:
                print("Will try to remove constraint", constraint)
            solutions = find_solutions(self, self.running, debug=debug)
            if solutions and len(solutions) == initial_solutions:
                if debug:
                    print("Still valid, move on")
                removed.append(str(constraint))
            else:
                if debug:
                    print("Nope, we'll keep that one")
                self.constraints.insert(0, constraint)
        if debug:
            if removed:
                print("We removed", removed)
                print("We now have", self.constraints)
            else:
                print("Nothing can be removed")
        self.remove_useless_fixed_values(initial_solutions, debug=debug)

    def remove_useless_fixed_values(self, initial_solutions, debug=False):
        # Now try to remove some fixed values
        initial_values = [
            (idx, cell.value)
            for idx, cell in enumerate(self.state)
            if cell.value != EMPTY
        ]
        if debug:
            print("Initial values", initial_values)
        removed = []
        for _ in range(len(initial_values)):
            idx, value = initial_values.pop()
            if debug:
                print(f"Will try to remove {idx+1}={value}")
            self.state[idx].value = EMPTY
            self.state[idx].options = self.domain[:]
            solutions = find_solutions(self, self.running, debug=debug)
            if debug:
                print("We now have", len(solutions), "solutions (initially was", initial_solutions, ")")
            if solutions and len(solutions) == initial_solutions:
                if debug:
                    print("Still valid, move on")
                removed.append((idx, value))
            else:
                if debug:
                    print("Nope, we'll keep that one")
                self.state[idx].value = value
                self.state[idx].options = []
        if debug:
            if removed:
                print("We removed", removed)
            else:
                print("Nothing can be removed")

    def check_solution(self, solution, debug=False):
        if debug:
            print("Check solution", solution)
        puzzle = self.clone()
        for idx, val in enumerate(solution):
            puzzle.set_value(idx, val)
        if puzzle.is_complete(debug=debug):
            return True
        if debug:
            for constraint in puzzle.constraints:
                print("Check constraint", constraint)
                print("->", constraint.check(puzzle, debug=debug))
        return False

    def clone(self):
        new_puzzle = Puzzle(running=self.running, width=self.width, height=self.height, domain=self.domain)
        new_puzzle.state = [c.clone() for c in self.state]
        new_puzzle.constraints = self.constraints[:]
        return new_puzzle
