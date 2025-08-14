from getsomepuzzle.engine.utils import to_grid


def test_to_grid1():
    assert to_grid("123456", 3, 2, int) == [
        [1, 2, 3],
        [4, 5, 6],
    ]


def test_to_grid2():
    assert to_grid("123456", 2, 3, int) == [
        [1, 2],
        [3, 4],
        [5, 6],
    ]
