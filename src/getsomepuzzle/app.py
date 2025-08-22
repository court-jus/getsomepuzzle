"""
Generate and play some logic puzzles
"""

import asyncio
import queue
import random
import threading

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW

from .engine.generator.background import BackgroundGenerator
from .engine.utils import to_grid
from .engine import constants
from .engine.constraints.parity import ParityConstraint
from .engine.constraints.groups import GroupSize
from .engine.constraints.motif import ForbiddenMotif
from .drawing.constraints import draw_constraint, draw_forbiddenmotif


MIN_PUZZLES = 5
MAX_PUZZLES = 10

class GetSomePuzzle(toga.App):
    def startup(self):
        # State
        self.current_puzzle = None
        self.readonly = set()
        self.puzzles = []

        # UI
        self.main_box = toga.Box(direction=COLUMN, background_color="lightgray")
        self.default_ui()
        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = self.main_box
        self.main_window.show()

        # Concurrency
        self.request_queue = queue.Queue()
        self.response_queue = queue.Queue()
        self.queue_size = 0
        self.gene = BackgroundGenerator("A", self.request_queue, self.response_queue)

    def on_running(self, *_a, **_kw):
        threading.Thread(target=self.gene.run, daemon=True).start()
        self.loop.call_soon(self.tick)

    def tick(self, *a, **_kw):
        print("Tick", self.queue_size, len(self.puzzles))
        if self.puzzles and not self.current_puzzle:
            self.get_and_show()
        if len(self.puzzles) < MIN_PUZZLES:
            while self.queue_size + len(self.puzzles) < MAX_PUZZLES:
                print("ALLEZ HOP ON GENERE")
                self.request_queue.put("go")
                self.queue_size += 1
                self.update_progress()
        try:
            print("tick waits for response")
            response = self.response_queue.get(timeout=0.01)
            print("tick has a response")
            self.queue_size -= 1
            self.update_progress()
        except queue.Empty:
            pass
        else:
            if response:
                self.puzzles.append(response)
                self.update_progress()
        self.loop.call_later(1, self.tick)

    def default_ui(self, *_a, **_kw):
        self.main_box.clear()
        buttons_box = toga.Box(direction=ROW)
        self.progress = toga.ProgressBar(max=100, value=0)
        self.queue_progress = toga.ProgressBar(max=100, value=0)
        self.go_button = toga.Button("Go", on_press=self.get_and_show, font_size=constants.FONT_SIZE, enabled=False)
        clear_button = toga.Button("Clr.", on_press=self.clear, font_size=constants.FONT_SIZE)
        reset_button = toga.Button("Rst.", on_press=self.reset, font_size=constants.FONT_SIZE)
        buttons_box.add(self.go_button, clear_button, reset_button)
        self.puzzle_input = toga.Box(direction=COLUMN)
        self.rules_canvas = toga.Box(direction=ROW)
        self.message_label = toga.Label("", font_size=constants.FONT_SIZE)
        self.main_box.add(
            buttons_box, self.queue_progress, self.progress,
            self.rules_canvas, self.puzzle_input, self.message_label
        )

    def update_progress(self):
        self.progress.value = len(self.puzzles) / 10 * 100
        self.queue_progress.value = self.queue_size / 10 * 100
        self.go_button.enabled = len(self.puzzles) > 0

    def get_and_show(self, *_a, **_kw):
        self.clear()
        if not self.puzzles:
            self.message_label.text = "No puzzle to run, please wait"
            return
        self.message_label.text = "Generating..."
        self.current_puzzle = self.puzzles.pop()
        self.update_progress()
        self.show_puzzle()
        self.message_label.text = "It's up to you now..."

    def show_puzzle(self):
        self.clear()
        pu = self.current_puzzle
        grid = to_grid(pu.state, pu.width, pu.height)
        # ⬅ ⮕ ⬆ ⬇ ⬌ ⬍  ⬉ ⬈ ⬊ ⬋
        parity_icons = {
            "left": "⬅",
            "right": "⮕",
            "horizontal": "⬌",
            "top": "⬆",
            "bottom": "⬇",
            "vertical": "⬍",
        }
        cell_constraints = {
            c.parameters["idx"]: {
                "constraint": c,
                "text": (
                    parity_icons[c.parameters["side"]]
                    if isinstance(c, ParityConstraint)
                    else c.parameters["size"]
                ),
            }
            for c in pu.constraints
            if isinstance(c, ParityConstraint) or isinstance(c, GroupSize)
        }
        for ridx, row in enumerate(grid):
            row_box = toga.Box(direction=ROW)
            for cidx, cell in enumerate(row):
                value = cell.value if cell.value else None
                bgcolor = constants.VALUE_BGCOLORS[cell.value]
                fgcolor = constants.CONSTRAST[bgcolor]
                cell_idx_in_state = cidx + ridx * pu.width
                readonly = value is not None
                if readonly:
                    self.readonly.add(cell_idx_in_state)
                cell_constraint = cell_constraints.get(cell_idx_in_state)
                cell_input = toga.Button(
                    cell_constraint["text"] if cell_constraint else ("." if readonly else ""),
                    id=f"{cidx},{ridx}",
                    on_press=self.user_input,
                    width=constants.BTN_SIZE,
                    height=constants.BTN_SIZE,
                    color=fgcolor,
                    background_color=bgcolor,
                    font_size=constants.FONT_SIZE,
                    font_weight="bold" if readonly else "normal"
                )
                if cell_constraint:
                    cell_constraint["constraint"].ui_widget = cell_input
                row_box.add(cell_input)
            self.puzzle_input.add(row_box)

        # Draw rules
        for c in pu.constraints:
            if isinstance(c, ForbiddenMotif):
                canvas = toga.Canvas(flex=1, width=constants.BTN_SIZE, height=constants.BTN_SIZE, background_color="purple")
                self.rules_canvas.add(canvas)
                draw_forbiddenmotif(c, canvas)
                c.ui_widget = canvas

    def user_input(self, widget):
        widget_id = widget.id
        w = self.current_puzzle.width

        cidx, ridx = map(int, widget_id.split(","))
        idx = ridx * w + cidx
        if idx in self.readonly:
            return
        current_value = self.current_puzzle.state[idx].value

        new_value = (current_value + 1) % (len(constants.DOMAIN) + 1)
        widget.style.background_color = constants.VALUE_BGCOLORS[new_value]
        widget.style.color = constants.CONSTRAST[constants.VALUE_BGCOLORS[new_value]]

        self.current_puzzle.state[idx].value = new_value
        self.check()

    def check(self, *_a, **_kw):
        if not self.current_puzzle:
            return
        if self.current_puzzle.check_solution(
            [c.value for c in self.current_puzzle.state]
        ):
            self.message_label.text = "You win"
        else:
            self.message_label.text = "Keep going"
        for c in sorted(self.current_puzzle.constraints):
            result = c.check(self.current_puzzle)
            result_text = "OK" if result else "KO"
            print(f"{result_text}: {str(c)}")

    def clear(self, *_a, **_kw):
        self.rules_canvas.clear()
        self.message_label.text = ""
        self.puzzle_input.clear()
        self.readonly = set()

    def reset(self, *_a, **_kw):
        if not self.current_puzzle:
            return
        self.current_puzzle.reset_user_input()
        self.clear()
        self.show_puzzle()



def main():
    return GetSomePuzzle()
