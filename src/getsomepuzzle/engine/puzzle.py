import random
import json
from .constraints import FixedValueConstraint
from .constraints.base import CellCentricConstraint
from .constants import DOMAIN, DEFAULT_SIZE, EMPTY, MAX_FORCABLE
from .errors import RuleConflictError, CannotApplyConstraint
from .cell import Cell
from .utils import line_export, get_neighbors

class Puzzle:
    def __init__(self, *, running, width=DEFAULT_SIZE, height=DEFAULT_SIZE, domain=None):
        self.running = running
        self.width = width
        self.height = height
        self.domain = domain if domain is not None else DOMAIN
        self.state = [Cell(self.domain) for _ in range(width * height)]
        self.constraints = []
        self.cplx = 0

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

    def mrv_free_cell(self):
        """Pick the free cell with fewest options (MRV), breaking ties by most filled neighbors."""
        cells = self.free_cells()
        if not cells:
            return None, None
        def score(cell_and_idx):
            cell, idx = cell_and_idx
            neighbors = get_neighbors(self.state, self.width, self.height, idx)
            filled_neighbors = sum(
                1 for n in neighbors if n is not None and self.state[n].value != EMPTY
            )
            return (len(cell.options), -filled_neighbors)
        return min(cells, key=score)

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
            sol, _ = tmp.solve_with_backtracking(running=self.running)
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
        count = 0
        while changed:
            changed = False
            for constraint in self.constraints:
                if only_idx is not None and only_idx not in constraint.influence(self):
                    continue
                before = [c.value for c in self.state]
                try:
                    constraint_result = constraint.apply(self)
                except CannotApplyConstraint:
                    raise CannotApplyConstraint(json.dumps({
                        "constraints": [str(constraint)],
                        "count": count,
                    }))
                if constraint_result:
                    if explain:
                        diff = "".join(str(c.value) if before[idx] == EMPTY and c.value != EMPTY else "." for idx, c in enumerate(self.state))
                        print("  Constraint", constraint, "gives us:")
                        print(" ", diff)
                    count += 1
                    changed = True
                    break
            globally_changed |= changed
            if auto_check:
                if not all(c.check(self) for c in self.constraints):
                    failed = [c for c in self.constraints if not c.check(self)]
                    raise CannotApplyConstraint(json.dumps({
                        "constraints": [str(c) for c in failed],
                        "count": count,
                    }))
        return count

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

    def solve(self, explain=False, max_steps=20):
        """Unified solving: apply_constraints + apply_with_force in a loop.
        Returns True if solved, False if stuck.
        Raises CannotApplyConstraint only on initial propagation failure
        (before any force has been applied)."""
        # Initial propagation — if this fails, the puzzle is truly unsolvable
        self.apply_constraints(explain=explain)
        if not self.free_cells():
            return self.is_complete()
        # Force + propagation loop
        for step in range(max_steps):
            try:
                force_changed = self.apply_with_force(explain=explain)
                if not self.free_cells():
                    return self.is_complete()
                changed = self.apply_constraints(explain=explain)
                if not self.free_cells():
                    return self.is_complete()
                if not changed and not force_changed:
                    break
            except CannotApplyConstraint:
                # Force + propagation created a contradiction — stuck, need backtracking
                return False
        return not self.free_cells() and self.is_complete()

    def solve_with_backtracking(self, running=None, level=0, explain=False, max_steps=20):
        """Full solver: propagation + force loop, then MRV backtracking if needed.
        Returns (solution_puzzle, steps) or (None, steps)."""
        st = self.clone()

        # Try full solve (propagation + force) first
        try:
            solved = st.solve(explain=explain, max_steps=max_steps)
        except CannotApplyConstraint:
            return None, 0
        if solved and st.is_complete():
            return st, 0
        # If force left the state corrupted, restart with propagation only
        if not st.is_possible():
            st = self.clone()
            try:
                st.apply_constraints()
            except CannotApplyConstraint:
                return None, 0
            if st.is_complete():
                return st, 0

        # Backtracking with MRV heuristic
        steps = 0
        max_bt_steps = 100000
        while steps <= max_bt_steps and (running is None or running.is_set()):
            if st.is_complete():
                return st, steps
            steps += 1
            cell, idx = st.mrv_free_cell()
            if cell is None:
                return None, steps
            for option in list(cell.options):
                clone = st.clone()
                clone.state[idx].set_value(option)
                sub_st, sub_steps = clone.solve_with_backtracking(
                    running=running, level=level + 1, max_steps=max_steps,
                )
                steps += sub_steps
                if sub_st is not None:
                    return sub_st, steps
                else:
                    st.state[idx].options.remove(option)
                    if not st.state[idx].options:
                        return None, steps
        return None, steps

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
        from .solver.puzzle_solver import find_solutions
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
