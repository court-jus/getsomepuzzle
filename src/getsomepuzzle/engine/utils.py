import json


def to_grid(strpuzzle, w, h, transformer=lambda x: x):
    return [[transformer(v) for v in strpuzzle[i * w : i * w + w]] for i in range(h)]


def to_rows(line, w, h):
    return [line[i * w : i * w + w] for i in range(h)]


def to_columns(line, w):
    return [line[i::w] for i in range(w)]


def state_to_str(pu):
    result = []
    grid = to_grid(pu.state, pu.width, pu.height, lambda x: x.value)
    result.append("-" * (len(grid[0]) * 4 + 1))
    for row in grid:
        result.append("= " + " | ".join([" " for c in row]) + " =")
        result.append("= " + " | ".join([str(c) if c > 0 else " " for c in row]) + " =")
        result.append("= " + " | ".join([" " for c in row]) + " =")
        result.append("-" * (len(grid[0]) * 4 + 1))
    return "\n".join(result)

def export_puzzle(pu):
    result = {
        "state": [{
            "value": c.value,
            "options": c.options,
        } for c in pu.state],
        "width": pu.width,
        "height": pu.height,
        "constraints": [{
            "cls": type(c).__name__,
            "parameters": c.parameters,
        } for c in pu.constraints],
    }
    return json.dumps(result, indent=4)

def import_puzzle(json_data):
    from .gspengine import Puzzle
    from .constraints import AVAILABLE_RULES

    data = json.loads(json_data)
    p = Puzzle(width=data["width"], height=data["height"])
    for idx, cell_data in enumerate(data["state"]):
        p.state[idx].value = cell_data["value"]
        p.state[idx].options = cell_data["options"]

    constraints = {c.__name__: c for c in AVAILABLE_RULES}
    for c in data["constraints"]:
        p.constraints.append(
            constraints[c["cls"]](**c["parameters"])
        )
    return p
