import pytest
from getsomepuzzle.engine.constraints.groups import GroupSize
from getsomepuzzle.engine.puzzle import Puzzle
from getsomepuzzle.engine.utils import FakeEvent

running = FakeEvent()


def make_puzzle(strpuzzle):
    strp = strpuzzle.strip()
    rows = strp.split("\n")
    values = [int(v) for v in strpuzzle.strip().replace("\n", "").replace(" ", "")]
    p = Puzzle(running=running, width=len(rows[0]), height=len(rows))
    for idx, val in enumerate(values):
        if val == 0:
            continue
        p.state[idx].value = val
        p.state[idx].options = []
    return p


def test_groupsize_valid():
    p = make_puzzle("""
    121
    121
    222
    """)
    sizes = [2, 5, 2, 2, 5, 2, 5, 5, 5]
    for idx, size in enumerate(sizes):
        assert GroupSize(indices=[idx], size=size).check(p, debug=True) is True


def test_groupsize_invalid():
    p = make_puzzle("""
    121
    121
    222
    """)
    sizes = [1, 2, 3, 4, 4, 3, 2, 1, 0]
    for idx, size in enumerate(sizes):
        assert GroupSize(indices=[idx], size=size).check(p, debug=True) is False

