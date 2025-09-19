import random
import time
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import FixedValueConstraint, ForbiddenMotif, QuantityAllConstraint, GroupSize, LetterGroup, ParityConstraint
from getsomepuzzle.engine.constants import EMPTY
from getsomepuzzle.engine.errors import CannotApplyConstraint, MaxIterRandomRule
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


def playground_contstraints_apply():
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



def main():
    for i in range(1):
        generate_a_puzzle()



if __name__ == "__main__":
    # main()
    # playground_contstraints_apply()
    # playground_find_solution()
    # playground_manually_check()
    compare_solvers_all()