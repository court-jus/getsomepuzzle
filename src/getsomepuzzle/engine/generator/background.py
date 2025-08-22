import time
import random

from ..gspengine import PuzzleGenerator


class BackgroundGenerator:
    def __init__(self, name):
        self.state = 0
        self.name = name

    def __repr__(self):
        return f"{self.name}: {self.state}"

    def work(self, running):
        return generate_one(running)


def generate_one(running):
    width = random.randint(3, 6)
    height = random.randint(3, 6)
    try:
        pg = PuzzleGenerator(width=width, height=height, running=running)
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
    while bp and bp > 2 and max_simplifications > 0:
        max_simplifications -= 1
        pu.simplify(solution)
        solution, bp = pu.find_solution(pu)
    if len(pu.find_solutions()) != 1:
        return None

    pu.clear_solutions()
    return pu
