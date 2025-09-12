import random
import time
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import FixedValueConstraint, ForbiddenMotif, QuantityAllConstraint
from getsomepuzzle.engine.utils import FakeEvent, state_to_str, line_export, line_import
from getsomepuzzle.engine.solver.puzzle_solver import find_solution, find_solutions
from getsomepuzzle.engine.generator.puzzle_generator import PuzzleGenerator

def generate_a_puzzle(load=None):

    start = time.time()
    running = FakeEvent()

    if load is None:
        width = random.randint(4, 6)
        height = random.randint(4, 7)
        pg = PuzzleGenerator(running=running, width=width, height=height)
        params = QuantityAllConstraint.generate_random_parameters(pg.puzzle)
        pg.puzzle.add_constraint(QuantityAllConstraint(**params))

        while True:
            try:
                added = pg.add_random_rule([])
            except RuntimeError:
                break
        pu = pg.puzzle
    else:
        pu = line_import(load)
        pu.running = running
    try:
        continue_looking = True
        while continue_looking:
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
                other = [sol for sol in other if sol[idx] == val]
    except ValueError:
        # This probably means that adding a fixed value constraint would fill the puzzle
        # The puzzle is probably boring as fuck
        return

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
        print(line_export(pu))
        for sol in solutions:
            print(sol)


def main():
    for i in range(100):
        generate_a_puzzle()



if __name__ == "__main__":
    main()
