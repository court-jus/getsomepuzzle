from getsomepuzzle.engine.utils import to_grid, to_groups, find_matching_group_neighbors


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

def test_to_groups():
    assert to_groups("1122", 2, 2) == [
        [0, 1],
        [2, 3],
    ]

def test_to_groups2():
    """
    1     22   1
      2 1  2   1
      22      11
    1  222
    """
    assert to_groups("1221212122111222", 4, 4) == [
        [0],
        [1, 2, 6],
        [3, 7, 10, 11],
        [4, 8, 9, 13, 14, 15],
        [5],
        [12]
    ]

def test_to_groups3():
    """
    212
    212
    222
    """
    assert to_groups("212212222", 3, 3) == [
        [0, 2, 3, 5, 6, 7, 8],
        [1, 4],
    ]


def test_find_matching_group_neighbors():
    assert set(find_matching_group_neighbors("220010000", 3, 3, [0, 1], "0")) == {2, 3}
