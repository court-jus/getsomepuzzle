import json
from functools import wraps


def to_grid(strpuzzle, w, h, transformer=lambda x: x):
    return [[transformer(v) for v in strpuzzle[i * w : i * w + w]] for i in range(h)]


def to_rows(line, w, h):
    return [line[i * w : i * w + w] for i in range(h)]


def to_columns(line, w):
    return [line[i::w] for i in range(w)]


def get_neighbors(strpuzzle, w, h, idx):
    maxidx = w * h - 1
    minidx = 0
    ridx = idx // w
    abv, bel, lft, rgt = idx - w, idx + w, idx - 1, idx + 1
    return (
        abv if abv >= minidx else None,
        bel if bel <= maxidx else None,
        lft if lft >= minidx and lft // w == ridx else None,
        rgt if rgt <= maxidx and rgt // w == ridx else None,
    )


def get_neighbors_same_value(strpuzzle, w, h, idx, transformer=lambda x: x):
    return [
        n for n in get_neighbors(strpuzzle, w, h, idx)
        if n is not None and transformer(strpuzzle[n]) == transformer(strpuzzle[idx])
    ] + [idx]


def to_groups(strpuzzle, w, h, transformer=lambda x: x):
    debug = False
    same_values = {
        idx: get_neighbors_same_value(strpuzzle, w, h, idx, transformer=transformer)
        for idx in range(len(strpuzzle))
    }
    groups = {}
    group_count = 0
    for idx, others in same_values.items():
        existing = {gidx: grp for gidx, grp in groups.items() if any([v in grp for v in others])}
        if debug:
            print("A", idx, others, existing, groups)
        if not existing:
            group_count += 1
            groups[group_count] = set(others)
            continue
        # Merge the groups
        new_gidx = list(existing.keys())[0]
        new_grp = existing[new_gidx].union(others)
        idx_remove = [i for i in existing.keys() if i != new_gidx]
        if debug:
            print("Add", others, "to", new_gidx, new_grp)
        for idx_to_remove in idx_remove:
            remove_grp = existing[idx_to_remove]
            del groups[idx_to_remove]
            if debug:
                print("Merge", remove_grp, "into", new_gidx, new_grp)
            new_grp = new_grp.union(remove_grp)
        groups[new_gidx] = groups[new_gidx].union(new_grp)
    return [sorted(list(grp)) for grp in sorted(groups.values())]


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
    from .puzzle import Puzzle
    from .constraints import AVAILABLE_RULES

    data = json.loads(json_data)
    domain = data.get("domain")
    p = Puzzle(running=running, width=data["width"], height=data["height"], domain=domain)
    for idx, cell_data in enumerate(data["state"]):
        value = cell_data.get("value", 0)
        options = p.domain[:] if value == 0 else [o for o in p.domain if o != value]
        p.state[idx].value = value
        p.state[idx].options = options

    constraints = {c.__name__: c for c in AVAILABLE_RULES}
    for c in data["constraints"]:
        p.constraints.append(
            constraints[c["cls"]](**c["parameters"])
        )
    return p

def line_export(pu):
    from .solver.puzzle_solver import find_solutions

    w, h = pu.width, pu.height
    domain = "".join(str(v) for v in pu.domain)
    values = "".join(str(c.value) for c in pu.state)
    constraints = ";".join(c.line_export() for c in pu.constraints)
    found_solutions = find_solutions(pu, pu.running)
    count = len(found_solutions)
    solutions = ";".join("".join(str(v) for v in sol) for sol in found_solutions)
    return f"{domain}_{w}x{h}_{values}_{constraints}_{count}:{solutions}"


def line_import(line):
    from .puzzle import Puzzle
    from .constraints import AVAILABLE_RULES

    line_format = line.count("_")
    domain, size, values, constraints, solutions = line.split("_")
    domain = [int(d) for d in domain]
    w, h = size.split("x")
    values = [int(v) for v in values]
    constraints = constraints.split(";")
    count, solutions = solutions.split(":")
    pu = Puzzle(running=None, width=int(w), height=int(h), domain=domain)
    for idx, cell in enumerate(pu.state):
        cell.value = values[idx]
        cell.options = pu.domain[:] if cell.value == 0 else []
    slugs = {
        kls.slug: kls
        for kls in AVAILABLE_RULES
    }
    for c in constraints:
        slug, parameters = c.split(":")
        kls = slugs[slug]
        parameters = kls.line_import(parameters)
        pu.constraints.append(kls(**parameters))
    return pu

def compute_level(*, duration, failures, total, **_):
    avg_duration = duration / total
    avg_failures = failures / total
    return int(avg_duration + 30 * avg_failures)

def timing(f):
    @wraps(f)
    def wrap(*args, **kw):
        ts = time.time()
        result = f(*args, **kw)
        te = time.time()
        print('func:%r took: %2.4f sec' % \
          (f.__name__, te-ts))
        return result
    return wrap

class FakeEvent:
    def is_set(self):
        return True
