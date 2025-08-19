"""
Generate and play some logic puzzles
"""

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW
from .engine.gspengine import PuzzleGenerator
from .engine.utils import to_grid
from .engine.constants import DOMAIN
from .engine.constraints.parity import ParityConstraint


VALUE_BGCOLORS = ["gray", "black", "white"]
VALUE_FGCOLORS = ["black", "white", "black"]
BTN_SIZE = 64
FONT_SIZE = 24

class GetSomePuzzle(toga.App):
    def startup(self):
        # State
        self.current_puzzle = None

        # UI
        main_box = toga.Box(direction=COLUMN)
        buttons_box = toga.Box(direction=ROW)
        self.progress = toga.ProgressBar(max=100, value=0)
        generate_button = toga.Button("Gen.", on_press=self.generate, font_size=FONT_SIZE)
        check_button = toga.Button("Chk.", on_press=self.check, font_size=FONT_SIZE)
        clear_button = toga.Button("Clr.", on_press=self.clear, font_size=FONT_SIZE)
        reset_button = toga.Button("Rst.", on_press=self.reset, font_size=FONT_SIZE)
        buttons_box.add(generate_button, check_button, clear_button, reset_button)
        self.puzzle_input = toga.Box(direction=COLUMN)
        self.rules = toga.Label("")
        self.message_label = toga.Label("", font_size=FONT_SIZE)
        main_box.add(
            buttons_box, self.progress, self.rules, self.puzzle_input, self.message_label
        )
        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = main_box
        self.main_window.show()

    def generate(self, *_a, **_kw):
        self.clear()
        self.message_label.text = "Generating..."
        puzzle_generated = False

        progress = 2
        def change_progress(val):
            self.progress.value = min(100, val + progress)
        while not puzzle_generated:
            progress = (progress + 1) % 100
            change_progress(2)
            try:
                pg = PuzzleGenerator(callback=change_progress)
                pu = pg.generate()
                if pu is None:
                    continue
                solution, bp = pu.find_solution(pu)
                if not bp:
                    continue
            except RuntimeError:
                continue
            else:
                puzzle_generated = True
        pu.apply_fixed_constraints()
        pu.clear_solutions()
        pu.remove_useless_rules()
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
        parity_icons = { "left": "<", "right": ">", "both": "≷"}
        parity_constraints = {
            c.parameters["idx"]: parity_icons[c.parameters["side"]]
            for c in pu.constraints
            if isinstance(c, ParityConstraint)
        }
        print("draw", parity_constraints)
        for ridx, row in enumerate(grid):
            row_box = toga.Box(direction=ROW)
            for cidx, cell in enumerate(row):
                value = cell.value if cell.value else None
                bgcolor = VALUE_BGCOLORS[cell.value]
                fgcolor = VALUE_FGCOLORS[cell.value]
                readonly = value is not None
                cell_idx_in_state = cidx + ridx * pu.width
                cell_input = toga.Button(
                    parity_constraints.get(cell_idx_in_state, ""),
                    id=f"{cidx},{ridx}",
                    enabled=not readonly,
                    on_press=self.user_input,
                    width=BTN_SIZE,
                    height=BTN_SIZE,
                    color=fgcolor,
                    background_color=bgcolor,
                    font_size=FONT_SIZE,
                )
                row_box.add(cell_input)
            self.puzzle_input.add(row_box)

    def user_input(self, widget):
        widget_id = widget.id
        w = self.current_puzzle.width

        cidx, ridx = map(int, widget_id.split(","))
        idx = ridx * w + cidx
        current_value = self.current_puzzle.state[idx].value

        new_value = (current_value + 1) % (len(DOMAIN) + 1)
        widget.style.background_color = VALUE_BGCOLORS[new_value]
        widget.style.color = VALUE_FGCOLORS[new_value]

        self.current_puzzle.state[idx].value = new_value

    def check(self, *_a, **_kw):
        if not self.current_puzzle:
            return
        if self.current_puzzle.check_solution(
            [c.value for c in self.current_puzzle.state]
        ):
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
