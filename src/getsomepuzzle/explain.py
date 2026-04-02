import sys

try:
    from getsomepuzzle.engine.utils import line_import
except ModuleNotFoundError:
    from .engine.utils import line_import


def explain(pu, max_steps=20):
    solved = pu.solve(explain=True, max_steps=max_steps)
    strstate = "".join(str(c.value) for c in pu.state)
    if solved:
        print(f"Solved! State: {strstate}")
    else:
        print(f"Could not solve by propagation+force alone. State: {strstate}")
        print(f"Remaining free cells: {len(pu.free_cells())}")


def main():
    line_repr = sys.argv[1]
    pu = line_import(line_repr)
    explain(pu)


if __name__ == "__main__":
    main()
