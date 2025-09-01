import random
import time
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import LetterGroup, FixedValueConstraint
from getsomepuzzle.engine.constraints.other_solution import OtherSolutionConstraint
from getsomepuzzle.engine.utils import FakeEvent, state_to_str, line_export, line_import
from getsomepuzzle.engine.solver.puzzle_solver import find_solution, find_solutions
from getsomepuzzle.engine.generator.puzzle_generator import PuzzleGenerator

def check_a_puzzle(lineRepr, to_check=[]):

    start = time.time()
    running = FakeEvent()

    pu = line_import(lineRepr)
    for prop in to_check:
        print("Check", prop)
        print(pu.check_solution(prop))

    pu.running = running
    pu.constraints.append(OtherSolutionConstraint(solution=[2,2,2,1,1,1,2,2,2,2,1,2,1,2,1]))
    print("Now:")
    print(pu.constraints)
    solutions = find_solutions(pu, running, max_solutions=10, debug=True)
    print(len(solutions), "solutions found")
    print(line_export(pu))
    for sol in solutions:
        print(sol)


def main():
    """
    2025-09-01T15:38:52 32s - 0f 3x5_220000000000020_FM:1.1;GS:0.3;GS:13.1_1:222111222212121
    """

    check_a_puzzle(
        "3x5_220000000000020_FM:1.1;GS:0.3;GS:13.1_1:222111222212121",
        to_check=[
            "222111222212121",
            "221212121212121",
            "221212122212121",
        ]
    )


if __name__ == "__main__":
    main()
