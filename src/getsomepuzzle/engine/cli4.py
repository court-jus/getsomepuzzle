import random
import time
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import FixedValueConstraint, ForbiddenMotif, QuantityAllConstraint, GroupSize, LetterGroup
from getsomepuzzle.engine.utils import FakeEvent, state_to_str, line_export, line_import
from getsomepuzzle.engine.solver.puzzle_solver import find_solution, find_solutions
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
                break
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
    pu = Puzzle(running=running, width=3, height=3)
    pu.state[2].value = 1
    pu.state[2].options = []
    pu.add_constraint(LetterGroup(indices=[2, 8], letter="A"))
    sol, bp, steps = find_solution(running, pu)
    print(pu)
    print(state_to_str(pu))
    print(pu.state)
    print("Solution can be found in", steps, "steps")
    pu.add_constraint(LetterGroup(indices=[1, 6], letter="B"), debug=True)
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
    pu = line_import("xxxxx")
    sol, bp, steps = find_solution(running, pu, debug=False)
    print(pu)
    print(state_to_str(pu))
    print(pu.state)
    print("Solution can be found in", steps, "steps")
    pu.apply_constraints()
    sol, bp, steps = find_solution(running, pu)
    print(pu)
    print(state_to_str(pu))
    print(pu.state)
    print("Solution can be found in", steps, "steps")


def main():
    for i in range(1):
        generate_a_puzzle()



if __name__ == "__main__":
    main()
    # playground_contstraints_apply()
    # playground_find_solution()
