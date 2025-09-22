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
                    print("# The puzzle has lost its interest", ratio)
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
                raise CannotApplyConstraint
        except CannotApplyConstraint:
            pu.constraints = [c for c in pu.constraints if c != added]
            banned.append(added)
        else:
            print("Rule added", added)
        # msg = f"{ticks: 4} - Banned: {len(banned): 5} - Added: {len(pu.constraints): 5}"
        # print(msg, end="\r")

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


def compare_solvers_all():
    asset = Path("..") / "assets" / "puzzles.txt"
    puzzles = [
        line
        for line in asset.read_text().split("\n")
        if line
    ]
    total = len(puzzles)
    print(f"{total} puzzles to check")
    for line in puzzles:
        print(line)
        compare_solvers(line)


def playground():
    rule_types = AVAILABLE_RULES[:]
    running = FakeEvent()
    pu = Puzzle(running=running, width=10, height=10)
    for i in range(150):
        try:
            rule = rule_types.pop(0)
        except IndexError:
            break

        params = rule.generate_random_parameters(pu)
        constraint = rule(**params)
        before = pu.clone()
        try:
            pu.add_constraint(constraint, auto_apply=False, auto_check=False)
            test_pu = pu.clone()
            test_pu.apply_constraints(auto_check=True)
            test_pu.apply_with_force()
            if not all(c.check(test_pu) for c in test_pu.constraints):
                raise RuleConflictError
        except (CannotApplyConstraint, RuleConflictError):
            pu = before

        can_add_again = True
        if hasattr(rule, "maximum_presence"):
            presence = len(list(c for c in pu.constraints if isinstance(c, rule)))
            if presence >= rule.maximum_presence(pu):
                can_add_again = False

        if can_add_again:
            rule_types.append(rule)
    pu.apply_fixed_constraints()
    print(line_export(pu))


def main():
    for i in range(1):
        generate_a_puzzle()


def solve_by_applying(line):
    pu = line_import(line)
    pu.apply_constraints()
    pu.apply_with_force()
    print(pu)
    print(state_to_str(pu))
    print(line_export(pu))


def all_possible_constraints():
    running = FakeEvent()
    pu = Puzzle(running=running, width=5, height=5)
    for rule in AVAILABLE_RULES:
        for params in rule.generate_all_parameters(pu):
            print(rule(**params))

if __name__ == "__main__":
    # main()
    # playground_constraints_apply()
    # playground_find_solution()
    # playground_manually_check()
    # compare_solvers_all()
    for i in range(10):
        playground()
    # solve_by_applying("12_10x10_0002000200002000010000000202000000000000000000000000002000000001000000000000000000000000021000000000_PA:62.left;FM:222;GS:9.1;LT:A.63.47;QA:1.8;PA:51.right;FM:22.02.20;GS:30.10;LT:B.13.82;PA:48.left;FM:1.1;GS:70.2;LT:C.11.40;PA:4.left;LT:D.52.43;PA:38.bottom;GS:99.2;LT:E.70.24;PA:20.top;GS:42.1;LT:F.5.55;PA:76.left;FM:1.1.2;GS:92.7;LT:G.73.53;GS:25.3;LT:H.22.46;PA:56.bottom;FM:001.001.101;GS:74.1;LT:I.8.97;PA:78.bottom;FM:11.10;FM:112;GS:57.3;LT:J.78.48;PA:88.top;LT:K.60.17;PA:15.right;FM:111.111.110;GS:49.1;LT:L.15.6;PA:61.top;LT:M.66.65;PA:57.right;FM:101.101.001;GS:3.8;LT:N.84.95;FM:100.110.111;PA:14.left;PA:67.right;LT:O.49.93;PA:85.top;PA:76.bottom;GS:62.1;PA:39.bottom;GS:86.7;PA:67.top;GS:36.4;GS:89.6;GS:37.10;GS:87.7;GS:61.6;GS:45.5;LT:P.76.1;PA:32.left;GS:2.1;LT:Q.35.4;LT:R.85.18;LT:S.67.29;LT:T.58.38_0:0")
    # solve_by_applying("12_10x10_1000000000000020000000000020000000100000001000000020000000000000001020000001000001000000000000000000_PA:11.bottom;FM:202.222;GS:18.9;LT:A.85.14;QA:2.11;PA:41.right;GS:62.9;LT:B.39.84;PA:58.left;FM:22.21.11;GS:86.5;LT:C.88.50;PA:19.bottom;FM:22;GS:25.9;LT:D.51.55;PA:83.top;FM:101.001.010;GS:21.4;LT:E.4.21;PA:12.left;FM:22.20;GS:59.7;LT:F.92.8;PA:72.left;FM:11.21.22;GS:2.6;LT:G.64.11;PA:54.bottom;FM:101.111;GS:71.10;LT:H.82.66;PA:27.top;GS:37.1;LT:I.31.76;PA:1.right;GS:67.4;LT:J.44.19;FM:112.112;GS:48.2;PA:30.bottom;PA:22.top;GS:33.7;FM:122;GS:73.1;GS:58.2;LT:K.52.97;PA:27.right;GS:7.10;PA:75.right;PA:87.top;GS:53.6;PA:91.right;FM:11.11;GS:43.2;LT:L.28.37;PA:36.left;LT:M.47.43;GS:24.2;LT:N.7.79;PA:48.top;PA:62.top;GS:41.1;GS:72.6;PA:74.left;LT:O.99.75;LT:P.61.49;LT:Q.16.33;LT:R.46.90;LT:S.80.25_0:0")
