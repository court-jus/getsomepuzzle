import random
import time
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import FixedValueConstraint, ForbiddenMotif, QuantityAllConstraint, GroupSize, LetterGroup, ParityConstraint, AVAILABLE_RULES
from getsomepuzzle.engine.constants import EMPTY
from getsomepuzzle.engine.errors import CannotApplyConstraint, MaxIterRandomRule, RuleConflictError
from getsomepuzzle.engine.utils import FakeEvent, state_to_str, line_export, line_import
from getsomepuzzle.engine.solver.puzzle_solver import find_solution, find_solutions, old_find_solution, old_find_solution_with_apply
from getsomepuzzle.engine.generator.puzzle_generator import PuzzleGenerator
from getsomepuzzle.engine.clitools import clear, write_at


def generate_a_puzzle(load=None):

    start = time.time()
    running = FakeEvent()

    if load is None:
        width = random.randint(4, 4)
        height = random.randint(4, 4)
        pg = PuzzleGenerator(running=running, width=width, height=height)
        # params = QuantityAllConstraint.generate_random_parameters(pg.puzzle)
        # pg.puzzle.add_constraint(QuantityAllConstraint(**params))

        while True:
            try:
                print("A?")
                added = pg.add_random_rule([], debug=False)
                print("A", line_export(pg.puzzle))
            except RuntimeError as exc:
                print("RTE while adding rule", exc)
                continue
        pu = pg.puzzle
    else:
        pu = line_import(load)
        pu.running = running
    try:
        continue_looking = True
        while continue_looking:
            print("B", line_export(pu))
            solutions = find_solutions(pu, running, max_solutions=10)
            continue_looking = (len(solutions) == 10)
            if len(solutions) == 1:
                break
            random.shuffle(solutions)
            sol1 = solutions[0]
            other = solutions[1:]
            while other:
                diff_values_per_idx = {
                    idx: len([sol for sol in other if sol[idx] != sol1[idx]])
                    for idx in range(len(sol1))
                    if [sol for sol in other if sol[idx] != sol1[idx]]
                }
                indices = sorted(diff_values_per_idx.items(), key=lambda i: i[1], reverse=True)
                idx = indices[0][0]
                val = sol1[idx]
                pu.add_constraint(FixedValueConstraint(idx=idx, val=val))
                print("C", line_export(pu))
                other = [sol for sol in other if sol[idx] == val]
                values = [c.value for c in pu.state]
                ratio = values.count(EMPTY) / len(values)
                if ratio < 0.7:
                    print(f"# The puzzle has lost its interest {ratio:5.2}")
                    raise ValueError
    except ValueError:
        # This probably means that adding a fixed value constraint would fill the puzzle
        print("F", line_export(pu))
        print("# The puzzle is probably boring as fuck")
        return

    print("D", line_export(pu))
    solutions = find_solutions(pu, running, max_solutions=10)
    if len(solutions) == 1:
        pu.remove_useless_rules()
        solutions = find_solutions(pu, running, max_solutions=10)
        path = Path("getsomepuzzle") / "new_puzzles.txt"
        line = line_export(pu)
        with open(path, "a") as fp:
            fp.write(line + "\n")
        print(time.time() - start, " - ", line)
    else:
        print("E", line_export(pu))
        for sol in solutions:
            print(sol)


def playground_constraints_apply():
    running = FakeEvent()
    pu = Puzzle(running=running, width=3, height=7)
    pu.state[1].value = 1
    pu.state[1].options = []
    pu.state[10].value = 2
    pu.state[10].options = []
    pu.state[16].value = 2
    pu.state[16].options = []
    pu.add_constraint(ParityConstraint(indices=[7], side="vertical"))
    sol, bp, steps = find_solution(running, pu)
    print(pu)
    print(state_to_str(pu))
    print(pu.state)
    print("Solution can be found in", steps, "steps")
    pu.add_constraint(ParityConstraint(indices=[6], side="right"))
    sol, bp, steps = find_solution(running, pu)
    print(pu)
    print(state_to_str(pu))
    print("Solution can be found in", steps, "steps")
    print("=" * 80)

    pu.apply_constraints()
    sol, bp, steps = find_solution(running, pu)
    print("Solution can be found in", steps, "steps")


def playground_find_solution():
    running = FakeEvent()
    pu = line_import("12_3x7_000000000000021000000_LT:A.11.18;PA:13.vertical;FM:12;PA:8.vertical;LT:B.20.19;LT:C.4.0_1:211222111222221222211")
    print(pu)
    print(state_to_str(pu))
    print(pu.state)
    sol, bp, steps = old_find_solution_with_apply(running, pu, debug=False)
    if not sol:
        print("Solution cannot be found in", steps, "steps")
    else:
        print("Solution can be found in", steps, "steps")


def playground_manually_check():
    width = random.randint(4, 4)
    height = random.randint(4, 4)
    running = FakeEvent()
    pg = PuzzleGenerator(running=running, width=width, height=height)
    pu = pg.puzzle

    rule_count = 0
    ticks = 0
    banned = []

    while ticks < 1000:
        ticks += 1
        try:
            added = pg.add_random_rule(banned, debug=False, auto_apply=False, auto_check=False)
        except MaxIterRandomRule:
            break
        try:
            clone = pu.clone()
            sol, bp, steps = find_solution(running, clone, debug=False)
            if not clone.is_valid() or sol is None:
                raise CannotApplyConstraint(str(added))
        except CannotApplyConstraint:
            pu.constraints = [c for c in pu.constraints if c != added]
            banned.append(added)
        else:
            print("Rule added", added)
        # msg = f"{ticks: 4} - Banned: {len(banned): 5} - Added: {len(pu.constraints): 5}"
        # print(f"\033[2K{msg}", end="\r")

    print()
    print(line_export(pu))
    sol, bp, steps = find_solution(running, pu, debug=False)
    print(pu)
    print(state_to_str(pu))
    print(pu.state)
    print("Solution can be found in", steps, "steps")
    print(sol)
    print(state_to_str(sol))
    print(sol.state)


def compare_solvers(line):
    running = FakeEvent()
    pu = line_import(line)
    ostart = time.time()
    old_find_solution(running, pu)
    oend = time.time()
    print("OLD ok")
    owstart = time.time()
    old_find_solution_with_apply(running, pu)
    owend = time.time()
    print("OWA ok")
    nstart = time.time()
    find_solution(running, pu)
    nend = time.time()
    print(f"OLD {oend - ostart:.4} OWA {owend - owstart:.4} NEW {nend - nstart:.4} DLT {(nend - nstart) - (oend - ostart):.4}")


def apply_to_all(what_to_apply):
    asset = Path("..") / "assets" / "puzzles.txt"
    puzzles = [
        line
        for line in asset.read_text().split("\n")
        if line
    ]
    total = len(puzzles)
    print(f"{total} puzzles to check")
    for line in puzzles:
        what_to_apply(line)


def playground():
    clear()
    rule_types = AVAILABLE_RULES[:]
    running = FakeEvent()
    pu = Puzzle(running=running, width=3, height=3)
    max_steps = 4
    banned = []
    # Generate all possible constraints
    all_constraints = []
    for rule in AVAILABLE_RULES:
        for params in rule.generate_all_parameters(pu):
            all_constraints.append(rule(**params))
    write_at(0, 30, "All: "+ str(len(all_constraints)))
    random.shuffle(all_constraints)

    izgood = False
    while all_constraints:
        bla = len(all_constraints)
        constraint = all_constraints.pop()
        if any(c == constraint for c in banned):
            continue
        before = pu.clone()
        try:
            test_pu = before.clone()
            write_at(0, 2, f"Add {constraint}")
            test_pu.add_constraint(constraint, auto_apply=False, auto_check=False)
            solve_result = solve_by_applying(test_pu, max_steps=max_steps)
            write_at(0, 5, str(solve_result))
            if solve_result["solved"]:
                write_at(0, 3, f"{bla: 5} The puzzle can be solved in its current state")
                pu.add_constraint(constraint, auto_apply=False, auto_check=False)
                izgood = True
                break
            elif solve_result["step_reached"] >= max_steps:
                write_at(0, 3, f"{bla: 5} The puzzle is impossible")
                raise RuleConflictError
            elif solve_result["failed"]:
                write_at(0, 3, f"{bla: 5} The puzzle is impossible")
                raise RuleConflictError
            else:
                write_at(0, 3, f"{bla: 5} The puzzle has not enough constraint")
            if not all(c.check(test_pu) for c in test_pu.constraints):
                raise RuleConflictError
        except (CannotApplyConstraint, RuleConflictError) as exc:
            write_at(0, 3, f"{bla: 5} The constraint cannot be added: {exc}")
            pu = before
        else:
            pu = test_pu

        write_at(0, 15, line_export(pu), flush=True)

    if izgood:
        pu.apply_fixed_constraints()
        return pu



def solve_by_applying_all():
    asset = Path("..") / "assets" / "puzzles.txt"
    puzzles = [
        line
        for line in asset.read_text().split("\n")
        if line
    ]
    total = len(puzzles)
    print(f"{total} puzzles to check")
    for i in range(1):
        generate_a_puzzle()
    solved = 0
    solved_in_steps = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    unsolved = []
    times = []
    for line in puzzles:
        pu = line_import(line)
        solve_result = solve_by_applying(pu, progress=False)
        times.append(solve_result["duration"])
        if solve_result["solved"]:
            level = solve_result["step_reached"]
            solved_in_steps[level] += 1
            solved += 1
            with open(Path("..") / "assets" / f"level{level:02}.txt", "a") as fp:
                fp.write(line + "\n")
        else:
            unsolved.append(line)
        print(f"\033[2K{solved + len(unsolved)}/{total} - Solved: {solved} - steps: {solved_in_steps}", end="\r")
    print()
    print(f"Total: {total} - Solved: {solved} (unsolved: {len(unsolved)}) - steps: {solved_in_steps}")
    print(f"Example unsolved: {unsolved[0]}")
    print("Average time to solve run:", sum(times) / len(times))
    print()

def solve_by_applying(pu, max_steps=10, progress=True):
    start = time.time()
    #print("  => ", end="")
    #print("".join(str(c.value) for c in pu.state), end=" - ")
    current_step = 0
    solved = False
    failed = False
    while current_step <= max_steps:
        changed = False
        if progress:
            write_at(0, 7, f"  / {current_step}")
        if current_step % 2 == 0:
            try:
                changed = pu.apply_constraints(auto_check=True)
            except CannotApplyConstraint:
                if progress:
                    write_at(0, 8, "Failed on apply")
                failed = True
                break
        else:
            try:
                changed = pu.apply_with_force()
            except CannotApplyConstraint:
                write_at(0, 8, "Failed on force")
                failed = True
                break
        if not all(c.check(pu) for c in pu.constraints):
            if progress:
                write_at(0, 8, "Failed on check")
            failed = True
            break
        strstate = "".join(str(c.value) for c in pu.state)
        if progress:
            write_at(0, 9, f"{strstate}")
        if "0" not in strstate:
            if progress:
                write_at(0, 10, "Solved")
            solved = True
            break
        if current_step % 2 != 0 and not changed:
            if progress:
                write_at(0, 10, "NoChange")
            break
        current_step += 1
    return {
        "duration": time.time() - start,
        "state": "".join(str(c.value) for c in pu.state),
        "solved": solved,
        "failed": failed,
        "step_reached": current_step,
    }



def all_possible_constraints():
    running = FakeEvent()
    pu = Puzzle(running=running, width=3, height=3)
    # Generate all possible constraints
    all_constraints = []
    for rule in AVAILABLE_RULES:
        for params in rule.generate_all_parameters(pu):
            all_constraints.append(rule(**params))
    print("All:", len(all_constraints))
    # Randomize the content of the grid
    for cell in pu.state:
        cell.set_value(random.choice(cell.domain))
    generated_solution = [c.value for c in pu.state]
    print("Puzzle ready", generated_solution)
    # Add all the constraints that match
    print()
    total = len(all_constraints)
    for idx, constraint in enumerate(all_constraints):
        print(f"\033[2K{idx} / {total}", end="\r")
        if constraint.check(pu):
            pu.constraints.append(constraint)
    print()
    print("Puz. const.:", len(pu.constraints))
    total = len(pu.constraints)
    # Remove fixed value constraints
    pu.constraints = [c for c in pu.constraints if not isinstance(c, FixedValueConstraint)]
    random.shuffle(pu.constraints)

    checked = 0
    generated_solution = [c.value for c in pu.state]
    last_msg = ""
    print()
    nb_cells_checked = 0
    total_constraint_check = 0
    while checked < total:
        print(f"\033[2K{checked: 6} / {total: 6} - {nb_cells_checked: 6} {total_constraint_check: 6} - ({len(pu.constraints): 6}) {last_msg}", end="\r")
        checked += 1
        nb_cells_checked = 0
        total_constraint_check = 0
        # Remove one constraint
        constraint = pu.constraints.pop(0)
        last_msg = f"Remove {constraint}"
        # Go through each cell
        for cell_idx, cell_val in enumerate(generated_solution):
            nb_cells_checked += 1
            # For that cell, swap the value
            clone = pu.clone()
            opposite = [v for v in pu.domain if v != cell_val][0]
            clone.set_value(cell_idx, opposite)
            # Now, if any constraint is invalid, it means that we can remove
            # the popped constraint
            for c in clone.constraints:
                total_constraint_check += 1
                if not c.check(clone):
                    break
            else:
                # All constraints are still valid, it means that the popped
                # constraint was the only one that constrained this cell and
                # it must be kept
                pu.constraints.append(constraint)
                last_msg = f"Keep {constraint}"
                break

    print()
    #Show puzzle
    print(pu)
    print(state_to_str(pu))
    print(line_export(pu))
