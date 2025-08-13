"""
Generate and play some logic puzzles
"""

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW
from .engine.backpropagation import PuzzleGenerator
from .engine.constraints import AllDifferentConstraint
from .engine.utils import show_solution

class GetSomePuzzle(toga.App):
    def startup(self):
        """Construct and show the Toga application.

        Usually, you would add your application to a main content box.
        We then create a main window (with a name matching the app), and
        show the main window.
        """
        main_box = toga.Box(direction=COLUMN)
        solution_label = toga.Label("Your solution: ", margin=(0, 5))
        self.solution_input = toga.TextInput(flex=1)
        solution_box = toga.Box(direction=COLUMN, margin=5)
        solution_box.add(solution_label)
        solution_box.add(self.solution_input)
        button = toga.Button(
            "Generate puzzle",
            on_press=self.generate,
            margin=5,
        )

        main_box.add(solution_box)
        main_box.add(button)

        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = main_box
        self.main_window.show()

    async def generate(self, *_a, **_kw):
        print("=" * 80)
        size = 5
        puzzle_generated = False
        while not puzzle_generated:
            print("Trying to generate a puzzle...")
            try:
                pg = PuzzleGenerator(size)
                pu = pg.generate(AllDifferentConstraint())
                solution, bp = pu.find_solution(pu)
                if not bp:
                    continue
            except RuntimeError:
                continue
            else:
                print("Found puzzle with bp", bp)
                puzzle_generated = True
        show_solution(pu)
        pu.clear_solutions()
        solution, bp = pu.find_solution(pu)
        print("bp is A", bp)
        show_solution(pu)
        pu.apply_fixed_constraints()
        pu.clear_solutions()
        solution, bp = pu.find_solution(pu)
        print("bp is B", bp)
        show_solution(pu)
        if not bp:
            raise RuntimeError("Could not find a puzzle")
        max_simplifications = 30
        while bp and bp > 1 and max_simplifications > 0:
            print("will do one simplification")
            max_simplifications -= 1
            pu.simplify(solution)
            solution, bp = pu.find_solution(pu)
            print("S", bool(solution), "BP", bp)
        pu.clear_solutions()
        show_solution(pu)
        print(". . .", bp, ". . .")
        print(pu)
        show_solution(pu)
        print("-" * 80)
        c = False
        failures = 0


def main():
    return GetSomePuzzle()
