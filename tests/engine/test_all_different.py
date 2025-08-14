import random
import pytest
from getsomepuzzle.engine.constraints import AllDifferentConstraint
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
    "puzzle",
    ["""
    12354
    23541
    35412
    54123
    41235
    """],
)
def test_all_different_valid(puzzle):
    p = make_puzzle(puzzle)
    c = AllDifferentConstraint()
    assert c.check(p) is True


@pytest.mark.parametrize(
    "puzzle",
    [],
)
@pytest.mark.skip()
def test_all_different_invalid(puzzle):
    p = make_puzzle(puzzle)
    c = AllDifferentConstraint()
    assert c.check(p) is False

@pytest.mark.skip()
def test_all_different_generate():
    random.seed(0)
    p = Puzzle(5, 5)
    assert ForbiddenMotif.generate_random_parameters(p)["motif"] == ["13", "54"]
