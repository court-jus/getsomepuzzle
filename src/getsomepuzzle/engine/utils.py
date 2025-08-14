def to_grid(strpuzzle, w, h, transformer=lambda x: x):
    return [[transformer(v) for v in strpuzzle[i * w : i * w + w]] for i in range(h)]


def to_rows(line, w, h):
    return [line[i * w : i * w + w] for i in range(h)]


def to_columns(line, w):
    return [line[i::w] for i in range(w)]


def solution_to_str(pu):
    result = []
    grid = to_grid(pu.state, pu.width, pu.height, lambda x: x.value)
    result.append("-" * (len(grid[0]) * 4 + 1))
    for row in grid:
        result.append("= " + " | ".join([" " for c in row]) + " =")
        result.append("= " + " | ".join([str(c) if c > 0 else " " for c in row]) + " =")
        result.append("= " + " | ".join([" " for c in row]) + " =")
        result.append("-" * (len(grid[0]) * 4 + 1))
    return "\n".join(result)
