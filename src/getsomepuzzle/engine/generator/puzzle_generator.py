import random
from ..constraints import (
    FixedValueConstraint,
    AVAILABLE_RULES,
)
from ..constants import DEFAULT_SIZE
from ..gspengine import Puzzle
from ..utils import line_export


class PuzzleGenerator:
    def __init__(self, *, running, width=DEFAULT_SIZE, height=DEFAULT_SIZE, callback=None):
        # History of the constraints added
        self.callback = callback if callback is not None else lambda x:x
        self.running = running
        self.puzzle = Puzzle(running=self.running, width=width, height=height)
    def add_random_rule(self, banned_constraints, debug=False):
        max_iter = 1000
        while max_iter > 0 and self.running.is_set():
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
        while number_fixed > 0 and self.running.is_set():
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
        while has_solution and self.running.is_set():
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

    def add_random_rule_valid(self, banned_constraints, debug=False):
        solution = None
        while solution is None and self.running.is_set():
            if debug:
                print("Add random rule")
            new_constraint = self.add_random_rule(banned_constraints, debug=debug)
            if debug:
                print(" -> ", new_constraint)
            if debug:
                print("Check that puzzle is still solvable")
            try:
                solution, bp = self.puzzle.find_solution(self.puzzle)
            except RuntimeError:
                solution = None
            if solution is not None:
                break
            if debug:
                print(" -> Failed, remove the new constraint and ban it")
            self.puzzle.constraints = [c for c in self.puzzle.constraints if c != new_constraint]
            banned_constraints.append(new_constraint)
        if debug:
            print(" -> OK")
        return new_constraint


def generate_one(args):
    running, width, height = args
    while True:
        result = generate_once(running, width, height)
        if result is not None:
            return result


def generate_once(running, width, height):
    w = width if width is not None else random.randint(3, 6)
    h = height if height is not None else random.randint(3, 6)
    try:
        pg = PuzzleGenerator(width=w, height=h, running=running)
        pu = pg.generate()
        if pu is None:
            return None
        solution, bp = pu.find_solution(pu)
        if not bp:
            return None
    except RuntimeError:
        return None
    pu.apply_fixed_constraints()
    pu.clear_solutions()
    pu.remove_useless_rules()
    solution, bp = pu.find_solution(pu)
    pu.clear_solutions()
    if bp is None:
        return None
    max_simplifications = 30
    while bp and bp > 5 and max_simplifications > 0:
        max_simplifications -= 1
        pu.simplify(solution)
        solution, bp = pu.find_solution(pu)
    if len(pu.find_solutions()) != 1:
        return None

    pu.clear_solutions()
    return pu
