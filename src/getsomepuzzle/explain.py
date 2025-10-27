import sys

from getsomepuzzle.engine.utils import line_import


def explain(pu, max_steps=10):
    current_step = 0
    solved = False
    while current_step <= max_steps:
        changed = False
        print(f"{current_step}:")
        if current_step % 2 == 0:
            print("Apply constraints")
            changed = pu.apply_constraints(explain=True)
        else:
            print("Apply with force")
            changed = pu.apply_with_force(explain=True)
        strstate = "".join(str(c.value) for c in pu.state)
        print(f"State is now {strstate}")
        if "0" not in strstate:
            print("Solved!!")
            solved = True
            break
        if current_step % 2 != 0 and not changed:
            print("Nothing changed")
            break
        current_step += 1

def main():
    line_repr = sys.argv[1]
    pu = line_import(line_repr)
    explain(pu)


if __name__ == "__main__":
    main()
