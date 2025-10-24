import math
import random
from pathlib import Path

from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.constraints import FixedValueConstraint, AVAILABLE_RULES
from getsomepuzzle.engine.utils import FakeEvent, line_export


def buildapuzzle(width, height, ratio, verbose=False, progress=True):
    running = FakeEvent()
    solved = Puzzle(running=running, width=width, height=height)
    pu = solved.clone()
    # Randomize the content of the grid
    for idx, cell in enumerate(solved.state):
        v = random.choice(cell.domain)
        cell.set_value(v)
    generated_solution = [c.value for c in solved.state]

    # Decide how many pre-filled cells we want
    size = width * height
    prefilled = math.ceil(size * (1 - ratio))
    indices = list(range(size))
    random.shuffle(indices)
    if verbose:
        print(f"Will fill {prefilled} cells.")
    while prefilled > 0:
        prefilled -= 1
        idx = indices.pop()
        pu.state[idx].set_value(solved.state[idx].value)

    # Generate all possible constraints
    all_constraints = []
    for rule in [r for r in AVAILABLE_RULES if r != FixedValueConstraint]:
        for params in rule.generate_all_parameters(solved):
            constraint = rule(**params)
            if constraint.check(solved):
                all_constraints.append(constraint)
    total = len(all_constraints)
    random.shuffle(all_constraints)
    if verbose:
        print(f"{total} constraints to be tried.")

    # While the puzzle is not playable
    ratio = pu.compute_ratio()
    while ratio > 0 and all_constraints:
        # Add the first valid constraint
        while all_constraints:
            if progress:
                print(f"\033[2K[{ratio:5.2}] {len(all_constraints):5} / {total:5}", end="\r")
            constraint = all_constraints.pop(0)
            cloned = pu.clone()
            # First: apply previously added constraints
            changed_step1 = True
            while changed_step1:
                changed_step1 = cloned.apply_constraints() or cloned.apply_with_force()

            # Then: try to apply the new constraint and see if it helps
            cloned.constraints.append(constraint)
            changed_step2 = cloned.apply_constraints()
            if changed_step2:
                ratio = cloned.compute_ratio()
                break
            changed_step2 |= cloned.apply_with_force()
            if changed_step2:
                ratio = cloned.compute_ratio()
                break

        # We found a constraint that is helpful, add it to the resulting puzzle
        pu.constraints.append(constraint)

    if progress:
        print()
    ratio = cloned.compute_ratio()
    missing = math.ceil(size * ratio)
    if verbose:
        print(f"We managed to make a {ratio:5.2} filled puzzle with {missing} cells.")
    if ratio > 0.25:
        # Too bad, this puzzle is not good
        return None

    if ratio == 0:
        path = Path("getsomepuzzle") / "new_puzzles3.txt"
        line = line_export(pu)
        with open(path, "a") as fp:
            fp.write(line + "\n")
        return pu

    cloned = pu.clone()
    changed = True
    while changed:
        changed = cloned.apply_constraints() or cloned.apply_with_force()
    for _, idx in cloned.free_cells():
        if verbose:
            print(f"Will fill cell {idx} and save to another file")
        pu.set_value(idx, solved.state[idx].value)
    path = Path("getsomepuzzle") / "high_ratio.txt"
    line = line_export(pu)
    with open(path, "a") as fp:
        fp.write(line + "\n")
    return pu

if __name__ == "__main__":
    nb = 100
    minwidth = 4
    maxwidth = 6
    minheight = 4
    maxheight = 8
    minratio = 0.7
    maxratio = 0.85

    while nb:
        width = random.randint(minwidth, maxwidth)
        height = random.randint(minheight, maxheight)
        ratio = random.random() * (maxratio - minratio) + minratio
        print(f"Will make a {width}x{height} puzzle filled at {int((1-ratio) * 100): 3}%.")
        pu = buildapuzzle(width, height, ratio)
        if pu:
            print(line_export(pu))
        nb -= 1
