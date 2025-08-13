def to_grid(strpuzzle, w, h, transformer=lambda x: x):
    return [[transformer(v) for v in strpuzzle[i * w : i * w + w]] for i in range(h)]


def to_rows(line, w, h):
    return [line[i * w : i * w + w] for i in range(h)]


def to_columns(line, w):
    return [line[i::w] for i in range(w)]


def show_solution(pu):
    grid = to_grid(pu.state, pu.width, pu.height, lambda x: x.value)
    print("-" * (len(grid[0]) * 4 + 1))
    for row in grid:
        print("= " + " | ".join([" " for c in row]) + " =")
        print("= " + " | ".join([str(c) if c > 0 else " " for c in row]) + " =")
        print("= " + " | ".join([" " for c in row]) + " =")
        print("-" * (len(grid[0]) * 4 + 1))
