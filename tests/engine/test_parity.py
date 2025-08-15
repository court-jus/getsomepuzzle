import random
import pytest
from getsomepuzzle.engine.constraints import ParityConstraint
from getsomepuzzle.engine.gspengine import Puzzle


def make_puzzle(strpuzzle):
    strp = strpuzzle.strip()
    rows = strp.split("\n")
    values = [int(v) for v in strpuzzle.strip().replace("\n", "").replace(" ", "")]
    p = Puzzle(width=len(rows[0]), height=len(rows))
    for idx, val in enumerate(values):
        if val == 0:
            continue
        p.state[idx].value = val
        p.state[idx].options = []
    return p


@pytest.mark.parametrize(
    "puzzle, idx, side, valid",
    [
        (
            """
        123
        231
        213
        """,
            0,
            "right",
            True,
        ),
        (
            """
        123
        231
        213
        """,
            2,
            "left",
            True,
        ),
        (
            """
        123
        231
        213
        """,
            3,
            "right",
            False,
        ),
        (
            """
        12345
        24568
        """,
            2,
            "left",
            True,
        ),
        (
            """
        12345
        24568
        """,
            2,
            "right",
            True,
        ),
        (
            """
        12345
        24568
        """,
            7,
            "left",
            False,
        ),
        (
            """
        12345
        24568
        """,
            7,
            "right",
            False,
        ),
        (
            """
        22212
        """,
            2,
            "right",
            True,
        ),
        (
            """
        22212
        """,
            2,
            "left",
            False,
        ),
        (
            """
        222121
        """,
            1,
            "right",
            True,
        ),
    ],
)
def test_parity(puzzle, idx, side, valid):
    p = make_puzzle(puzzle)
    c = ParityConstraint(idx=idx, side=side)
    assert c.check(p) is valid


@pytest.mark.skip()
def test_parity_generate():
    random.seed(0)
    p = Puzzle(5, 5)
    generated = ParityConstraint.generate_random_parameters(p)
    assert generated["idx"] == 2
    assert generated["side"] == "right"
