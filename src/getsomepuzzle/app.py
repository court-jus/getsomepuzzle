"""
Generate and play some logic puzzles
"""

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW
from .engine.gspengine import PuzzleGenerator
from .engine.constraints import AllDifferentConstraint
from .engine.utils import to_grid
from .engine.constants import DOMAIN


class GetSomePuzzle(toga.App):
    def startup(self):
        self.current_puzzle = None
        main_box = toga.Box(direction=COLUMN)
        buttons_box = toga.Box(direction=ROW)
        generate_button = toga.Button(
            "Gen.",
            on_press=self.generate,
            margin=5,
        )
        check_button = toga.Button(
            "Chk.",
            on_press=self.check,
            margin=5
        )
        clear_button = toga.Button(
            "Clr.",
            on_press=self.clear,
            margin=5,
        )
        reset_button = toga.Button(
            "Rst.",
            on_press=self.reset,
            margin=5,
        )
        buttons_box.add(generate_button, check_button, clear_button, reset_button)
        puzzle_box = toga.Box(direction=ROW)
        self.puzzle_input = toga.Box(direction=COLUMN)
        puzzle_box.add(self.puzzle_input)
        self.rules = toga.Label("")
        self.message_label = toga.Label("")
        main_box.add(buttons_box, self.rules, puzzle_box, self.message_label)

        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = main_box
        self.main_window.show()

    def generate(self, *_a, **_kw):
        self.clear()
        self.message_label.text = "Generating..."
        puzzle_generated = False
        while not puzzle_generated:
            try:
                pg = PuzzleGenerator()
                pu = pg.generate()
                solution, bp = pu.find_solution(pu)
                if not bp:
                    continue
            except RuntimeError:
                continue
            else:
                puzzle_generated = True
        pu.apply_fixed_constraints()
        pu.clear_solutions()
        solution, bp = pu.find_solution(pu)
        pu.clear_solutions()
        if bp is None:
            raise RuntimeError("Could not find a puzzle")
        max_simplifications = 30
        while bp and bp > 1 and max_simplifications > 0:
            max_simplifications -= 1
            pu.simplify(solution)
            solution, bp = pu.find_solution(pu)
        pu.clear_solutions()
        c = False
        failures = 0
        self.current_puzzle = pu
        self.show_puzzle()
        self.message_label.text = "It's up to you now..."

    def show_puzzle(self):
        self.clear()
        pu = self.current_puzzle
        self.rules.text = repr(pu)
        grid = to_grid(pu.state, pu.width, pu.height)
        for ridx, row in enumerate(grid):
            row_box = toga.Box(direction=ROW)
            for cidx, cell in enumerate(row):
                value = (cell.value if cell.value else None)
                readonly = value is not None
                cell_input = toga.Button(
                    value,
                    id=f"{cidx},{ridx}",
                    enabled=not readonly,
                    style=Pack(width=48, height=48),
                    on_press=self.user_input,
                )
                row_box.add(cell_input)
            self.puzzle_input.add(row_box)

    def user_input(self, widget):
        w = self.current_puzzle.width
        widget_id = widget.id
        try:
            widget_value = int(widget.text)
        except ValueError:
            widget_value = 0
        new_value = (widget_value + 1) % (len(DOMAIN) + 1)
        widget.text = new_value if new_value > 0 else ""

        cidx, ridx = map(int, widget_id.split(","))
        idx = ridx * w + cidx
        self.current_puzzle.state[idx].value = new_value

    def check(self, *_a, **_kw):
        if not self.current_puzzle:
            return
        if self.current_puzzle.check_solution([c.value for c in self.current_puzzle.state]):
            self.message_label.text = "You win"
        else:
            self.message_label.text = "Keep going"
        text = [
            "Rules:",
            f"Puzzle size is {len(self.current_puzzle.state)}",
            f"Possible values: {DOMAIN}",
        ]
        for c in sorted(self.current_puzzle.constraints):
            if c.check(self.current_puzzle):
                text.append(str(c))
            else:
                text.append("FAIL " + str(c))
        self.rules.text = "\n".join(text)

    def clear(self, *_a, **_kw):
        self.rules.text = ""
        self.message_label.text = ""
        self.puzzle_input.clear()

    def reset(self, *_a, **_kw):
        self.current_puzzle.reset_user_input()
        self.clear()
        self.show_puzzle()

def main():
    return GetSomePuzzle()
