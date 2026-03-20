import time
from ..constraints.other_solution import OtherSolutionConstraint
from ..constants import MAX_STEPS, EMPTY
from ..errors import CannotApplyConstraint, TooEmpty
from ..utils import line_export


def find_solution(running, puzzle, level=0, debug=False):
    start = time.time()
    if debug:
        print(" " * level, "find_solution for", line_export(puzzle))
    st = puzzle.clone()
    try:
        st.apply_constraints()
    except CannotApplyConstraint:
        if debug:
            print(" " * level, "cannot apply constraints, consider this as unsolvable")
        return None, None, 0
    # if not st.is_forcable():
    #     raise TooEmpty
    log_history = []
    steps = 0
    while steps <= MAX_STEPS and running.is_set():
        # time.sleep(1)
        if st.is_complete(debug=False):
            break
        steps += 1
        cell, idx = st.first_free_cell()
        if cell is None:
            return None, None, steps
        for option in cell.options:
            # time.sleep(0.5)
            if debug:
                print(" " * level, f"Will try to set {idx + 1} = {option} ({cell.options}) and recurse into that")
            clone = st.clone()
            clone.state[idx].set_value(option)
            sub_st, sub_level, sub_steps = find_solution(running, clone, level=level+1, debug=debug)
            if sub_st is not None:
                return sub_st, sub_level, (sub_steps + steps)
            else:
                if debug:
                    print(" " * level, f"Nope, we should remove {option} from options for {idx+1}")
                st.state[idx].options.remove(option)
                if not st.state[idx].options:
                    return None, None, steps

    if not st.is_complete(debug=False):
        return None, None, steps
    return st, level, steps

def find_solutions(puzzle, running, max_solutions=2, debug=False):
    initial_state = puzzle.clone()
    initial_state.apply_fixed_constraints(debug=debug)
    max_explorations = max_solutions
    while max_explorations > 0 and running.is_set():
        max_explorations -= 1
        try:
            solution, _, _ = find_solution(running, initial_state, debug=debug)
        except RuntimeError:
            break                
        if debug:
            print("* Found solution", solution.state if solution is not None else None)
        if solution is None:
            break

        # Forbid this solution
        found_solution = [c.value for c in solution.state]
        initial_state.constraints.append(
            OtherSolutionConstraint(solution=found_solution)
        )

    solutions = []
    for constraint in initial_state.constraints:
        if isinstance(constraint, OtherSolutionConstraint):
            solutions.append(constraint.parameters["solution"])
    return solutions
