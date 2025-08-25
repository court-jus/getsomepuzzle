import random
import pytest
from getsomepuzzle.engine.constraints.motif import ForbiddenMotif
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


@pytest.mark.parametrize(
    "motif, puzzle",
    [
        (
            ["12", "21"],
            """
        123
        456
        """,
        ),
        (
            ["12", "21"],
            """
        1232
        4212
        """,
        ),
        (
            ["12", "21"],
            """
        312
        312
        """,
        ),
        (
            ["12", "21", "34"],
            """
        123
        213
        433
        """,
        ),
    ],
)
def test_forbidden_motif_valid(motif, puzzle):
    motif = ForbiddenMotif(motif=motif)
    p = make_puzzle(puzzle)
    assert motif.check(p) is True


@pytest.mark.parametrize(
    "motif, puzzle",
    [
        (
            ["12", "21"],
            """
        123
        216
        """,
        ),
        (
            ["12", "21"],
            """
        1212
        4221
        """,
        ),
        (
            ["12", "21"],
            """
        312412
        312421
        """,
        ),
        (
            ["12", "21", "34"],
            """
        312412
        321421
        334421
        """,
        ),
        (
            ["11", "22"],
            """
        0111
        1122
        1221
        0221
        """,
        )
    ],
)
def test_forbidden_motif_invalid(motif, puzzle):
    motif = ForbiddenMotif(motif=motif)
    p = make_puzzle(puzzle)
    assert motif.check(p) is False


@pytest.mark.skip()
def test_forbidden_motif_generate():
    random.seed(0)
    p = Puzzle(running=running, width=5, height=5)
    assert ForbiddenMotif.generate_random_parameters(p)["motif"] == ["13", "54"]
