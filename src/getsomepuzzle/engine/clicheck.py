import random
import time
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import LetterGroup, FixedValueConstraint
from getsomepuzzle.engine.utils import FakeEvent, state_to_str, line_export, line_import
from getsomepuzzle.engine.solver.puzzle_solver import find_solution, find_solutions
from getsomepuzzle.engine.generator.puzzle_generator import PuzzleGenerator

def check_a_puzzle(lineRepr, to_check=[]):

    start = time.time()
    running = FakeEvent()

    pu = line_import(lineRepr)
    for prop in to_check:
        print(prop, "is", "valid" if pu.check_solution(prop) else "not valid")

    pu.running = running
    solutions = find_solutions(pu, running, debug=False)
    print(len(solutions), "solutions found")
    print(line_export(pu))
    for sol in solutions:
        print("".join(str(c) for c in sol))


def hpu(line):
    data = line.split("_")
    dimensions, state, rules = data[1:4]
    return "_".join([dimensions, state, rules])


def recheck_puzzles():
    raw_already_done = (Path("..") / "assets" / "rechecked.txt").read_text().split("\n")
    already_done = [
        hpu(line)
        for line in raw_already_done
        if line.strip()
    ]
    print(len(already_done), "already done")
    asset = Path("..") / "assets" / "puzzles.txt"
    puzzles = [
        line
        for line in asset.read_text().split("\n")
        if line and hpu(line) not in already_done
    ]
    total = len(puzzles)
    print(f"{total} puzzles to recheck")
    with open(Path("..") / "assets" / "rechecked.txt", "a") as fp:
        done = 0
        for puzzle in puzzles:
            pu = line_import(puzzle)
            pu.running = FakeEvent()
            if check_constraints(puzzle):
                fp.write(line_export(pu) + "\n")
            else:
                print("Eliminate", line_export(pu))
            done += 1
            if done % 10 == 0:
                print(f"{done}/{total}")


def check_constraints(puz):
    pu = line_import(puz)
    for c in pu.constraints:
        for o in pu.constraints:
            if c == o:
                continue
            if c.conflicts(o):
                print(c, "conflicts with", o)
                return False
    return True

def list_constraints():
    asset = Path("..") / "assets" / "puzzles.txt"
    puzzles = [
        line
        for line in asset.read_text().split("\n")
        # if line and hpu(line) not in already_done
    ]
    total = len(puzzles)
    print(f"{total} puzzles")
    all_constraints = set()
    for line in puzzles:
        if not line:
            continue
        pu = line_import(line)
        for c in pu.constraints:
            all_constraints.add(c.signature())
    lst = sorted(list(all_constraints))
    print(f"{len(lst)} different constraint signatures")
    filtered = []
    # for sig in all_constraints:
    #     for oth in lst:
    #         sig_slug, sig_data = sig.split(":")
    #         oth_slug, oth_data = oth.split(":")
    #         if sig_slug != oth_slug:
    #             continue
    #         if sig_slug != "FM":
    #             continue
    #         if sig_data.replace("1", "A").replace("2", "B") != oth_data.replace("2", "A").replace("1", "B"):
    #             continue
    #         filtered.append(oth)
    final = [sig for sig in lst if sig not in filtered]
    print(f"{len(final)} unique signatures")
    print(final)

# check_a_puzzle(
#     "12_6x7_000000000000000000000000100000000000000010_LT:A.36.31;FM:2.1;PA:10.left;PA:17.top;PA:26.bottom_1:111111121212121212121212121212221212222212",
#     to_check=[
#         [int(c) for c in "121211121212121212121212121212221212222212"],
#         [int(c) for c in "111211121212121212121212121212221212222212"],
#     ]
# )

# print(check_constraints("12_3x3_010000200_FM:21;FM:12_1:212212212"))
recheck_puzzles()
# list_constraints()
