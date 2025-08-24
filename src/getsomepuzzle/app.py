"""
Generate and play some logic puzzles
"""

import threading
import random
import concurrent.futures
from pathlib import Path
import time
import datetime

import toga
from toga.style import Pack
from toga.style.pack import COLUMN, ROW

from .engine.generator.puzzle_generator import generate_one
from .engine.utils import to_grid, line_import, line_export
from .engine import constants
from .engine.constraints.parity import ParityConstraint
from .engine.constraints.groups import GroupSize
from .engine.constraints.motif import Motif
from .drawing.constraints import draw_constraint, draw_motif
from .drawing.cell import draw_cell

MIN_PUZZLES = 5
MAX_PUZZLES = 10

class GetSomePuzzle(toga.App):
    def startup(self):
        # State
        self.current_puzzle = None
        self.current_line = None
        self.readonly_cells = set()
        self.puzzle_count = 0
        self.victories = 0
        self.failures = 0
        self.readonly = True
        self.puzzles = []
        self.solving_state = {}
        self.paused = True
        self.idle_start = None
        self.idle_time = 0

        # UI
        self.main_box = toga.Box(direction=COLUMN, background_color="lightgray")
        self.default_ui()
        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = self.main_box
        self.main_window.on_hide = self.on_hide
        self.main_window.show()

        # Concurrency
        self.request_queue = []
        self.response_queue = []
        self.executor = concurrent.futures.ThreadPoolExecutor(max_workers=2)
        self.running = threading.Event()

    def on_hide(self, *_a, **_kw):
        if self.idle_start is not None:
            self.idle_time += time.time() - self.idle_start
        if not self.paused:
            self.toggle_pause()

    def toggle_pause(self, *_a, **_kw):
        if self.idle_start is not None:
            self.idle_time += time.time() - self.idle_start
            self.idle_start = None
        if self.paused:
            self.paused = False
            self.pause_button.text = "⏸"
        else:
            self.paused = True
            self.pause_button.text = "🏃"
            self.idle_start = time.time()

    def on_running(self, *_a, **_kw):
        self.load_puzzles()
        self.running.set()
        self.loop.call_soon(self.tick)

    def on_exit(self, *_a, **_kw):
        self.running.clear()
        self.executor.shutdown(cancel_futures=True)
        return True

    def tick(self, *a, **_kw):
        if self.puzzles and not self.current_puzzle:
            self.get_and_show()
        if len(self.puzzles) < MIN_PUZZLES and self.running.is_set():
            while len(self.request_queue) + len(self.response_queue) + len(self.puzzles) < MAX_PUZZLES:
                self.request_queue.append("go")
                self.update_progress()
        while len(self.request_queue) > 0 and self.running.is_set():
            request = self.request_queue.pop()
            future = self.executor.submit(generate_one, (self.running, None, None))
            self.response_queue.append(future)

        new_response_queue = []
        while len(self.response_queue) > 0:
            future = self.response_queue.pop()
            if not future.done():
                new_response_queue.append(future)
                continue
            result = future.result()
            line = line_export(result)
            self.puzzles.append((line, result))
        self.response_queue = new_response_queue

        self.update_progress()
        self.loop.call_later(0.2, self.tick)

    def load_puzzles(self):
        path = Path(__file__).parent / Path("resources/puzzles.txt")
        print(path)
        data = path.read_text(encoding="utf-8")
        puzzles = []
        for line in data.split("\n"):
            if not line or line.startswith("#"):
                continue
            puzzles.append((line, line_import(line)))
        random.shuffle(puzzles)
        self.puzzle_count = len(puzzles)
        self.puzzles = puzzles
        self.update_progress()

    def default_ui(self, *_a, **_kw):
        self.main_box.clear()
        buttons_box = toga.Box(direction=ROW)
        self.progress = toga.ProgressBar(max=100, value=0)
        self.queue_progress = toga.ProgressBar(max=100, value=0)
        self.progress_label = toga.Label("")
        self.go_button = toga.Button("Go", on_press=self.get_and_show, font_size=constants.FONT_SIZE, enabled=False)
        clear_button = toga.Button("Clr.", on_press=self.clear, font_size=constants.FONT_SIZE)
        reset_button = toga.Button("Rst.", on_press=self.reset, font_size=constants.FONT_SIZE)
        self.pause_button = toga.Button("⏸", on_press=self.toggle_pause, font_size=constants.FONT_SIZE)
        buttons_box.add(self.go_button, clear_button, reset_button, self.pause_button)
        self.puzzle_input = toga.Box(direction=COLUMN)
        self.rules_canvas = toga.Box(direction=ROW)
        self.message_label = toga.Label("", font_size=constants.FONT_SIZE)
        self.main_box.add(
            buttons_box, self.queue_progress, self.progress,
            self.progress_label,
            self.rules_canvas, self.puzzle_input, self.message_label
        )

    def update_progress(self):
        remaining = len(self.puzzles)
        done = self.puzzle_count - remaining
        self.progress.value = remaining / self.puzzle_count * 100
        self.queue_progress.value = len(self.response_queue) / 10 * 100
        self.progress_label.text = f"Puz: {done}/{self.puzzle_count}. W: {self.victories}. F: {self.failures}"
        if not self.readonly and not self.paused:
            start = self.solving_state.get("start")
            if start is not None:
                duration = time.time() - start
                if self.idle_time > 0:
                    duration -= self.idle_time
                self.message_label.text = str(int(duration))
        self.go_button.enabled = remaining > 0

    def get_and_show(self, *_a, **_kw):
        self.clear()
        if not self.puzzles:
            self.message_label.text = "No puzzle to run, please wait"
            return
        self.message_label.text = "Generating..."
        self.current_line, self.current_puzzle = self.puzzles.pop()
        self.solving_state = {
            "line": self.current_line,
            "start": time.time(),
            "failures": 0,
        }
        self.idle_time = 0
        self.idle_start = None
        if self.paused:
            self.toggle_pause()
        self.log("start", self.current_line)
        self.readonly = False
        self.update_progress()
        self.show_puzzle()
        self.message_label.text = "It's up to you now..."

    def show_puzzle(self):
        self.clear()
        pu = self.current_puzzle
        grid = to_grid(pu.state, pu.width, pu.height)
        for ridx, row in enumerate(grid):
            row_box = toga.Box(direction=ROW)
            for cidx, cell in enumerate(row):
                value = cell.value if cell.value else None
                cell_idx_in_state = cidx + ridx * pu.width
                readonly = value is not None
                if readonly:
                    self.readonly_cells.add(cell_idx_in_state)
                cell_constraint = self.current_puzzle.get_cell_constraint(cell_idx_in_state)
                cell_input = toga.Canvas(
                    flex=1,
                    id=f"{cidx},{ridx}",
                    on_press=self.user_input,
                    width=constants.BTN_SIZE,
                    height=constants.BTN_SIZE,
                )
                draw_cell(cell_input, cell, cell_constraint)
                if cell_constraint:
                    cell_constraint["constraint"].ui_widget = cell_input
                row_box.add(cell_input)
            self.puzzle_input.add(row_box)

        # Draw rules
        for c in pu.constraints:
            if isinstance(c, Motif):
                canvas = toga.Canvas(flex=1, width=constants.BTN_SIZE, height=constants.BTN_SIZE, background_color=c.bg_color)
                self.rules_canvas.add(canvas)
                draw_motif(c, canvas)
                c.ui_widget = canvas

    def user_input(self, widget, *_a, **_kw):
        if self.readonly or self.paused:
            return
        widget_id = widget.id
        w = self.current_puzzle.width

        cidx, ridx = map(int, widget_id.split(","))
        idx = ridx * w + cidx
        if idx in self.readonly_cells:
            return
        cell = self.current_puzzle.state[idx]
        current_value = cell.value
        new_value = (current_value + 1) % (len(constants.DOMAIN) + 1)

        self.current_puzzle.state[idx].value = new_value
        cell_constraint = self.current_puzzle.get_cell_constraint(idx)
        draw_cell(widget, cell, cell_constraint)

        if not self.current_puzzle.free_cells():
            self.loop.call_later(1, self.check)

    def check(self, *_a, **_kw):
        if self.readonly or not self.current_puzzle:
            return
        if self.current_puzzle.check_solution(
            [c.value for c in self.current_puzzle.state]
        ):
            self.victories += 1
            self.message_label.text = "You win"
            self.readonly = True
            self.log("win", self.current_line)
            duration = time.time() - self.solving_state["start"]
            if self.idle_time:
                duration -= self.idle_time
            duration = int(duration)
            self.log("stats", self.current_line, log=f"{duration}s - {self.solving_state['failures']}f")
            self.loop.call_later(1, self.get_and_show)
        else:
            self.failures += 1
            self.solving_state["failures"] += 1
            self.log("fail", self.current_line)
            self.message_label.text = "Fail!!!"

    def clear(self, *_a, **_kw):
        self.rules_canvas.clear()
        self.message_label.text = ""
        self.puzzle_input.clear()
        self.readonly_cells = set()

    def reset(self, *_a, **_kw):
        if not self.current_puzzle:
            return
        self.current_puzzle.reset_user_input()
        self.clear()
        self.show_puzzle()

    def log(self, evt, line, **kw):
        now = datetime.datetime.now().replace(microsecond=0).isoformat()
        print(now, evt, line)
        if evt == "stats":
            msg = f"{now} {kw['log']} {line}"
            path = self.paths.data / "stats.txt"
            with path.open("a") as stats_file:
                stats_file.write(msg + "\n")

def main():
    return GetSomePuzzle()
