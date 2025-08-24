import random
from .constraints import FixedValueConstraint
from .constraints.base import CellCentricConstraint
from .constants import DOMAIN, DEFAULT_SIZE
from .cell import Cell
from .solver.puzzle_solver import find_solutions

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
        solutions = find_solutions(self, self.running)
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
            solutions = find_solutions(new_puzzle, self.running)
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
            solutions = find_solutions(new_puzzle, self.running)
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
