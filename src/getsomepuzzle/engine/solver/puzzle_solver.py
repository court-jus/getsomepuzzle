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

   
def old_find_solution(running, starting_state, debug=False):
    start = time.time()
    st = starting_state.clone()
    log_history = []
    steps = 0
    backpropagations = 0
    while steps <= MAX_STEPS and running.is_set():
        if st.is_complete(debug=debug):
            break
        if debug:
            print(st.state)
        steps += 1
        cell, idx = st.first_free_cell()
        if cell is None or not st.is_possible():
            if debug:
                print("Not possible anymore")
                print("HISTORY:")
                print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
            # Rewind history, until we find a moment where a value was fixed,
            # change that value and keep looking for solutions.
            if not log_history:
                if debug:
                    print("No history left, no solution found")
                return None, None, steps
            previous_line = st
            backpropagations += 1
            for hidx, line in enumerate(log_history[::-1]):
                cell_idx, chosen_value, options_remaining = line
                if debug:
                    print(f"We had chosen {cell_idx+1} = {chosen_value} and still had options {options_remaining}")
                if not options_remaining:
                    continue
                if debug:
                    print("We could have chosen another option, let's try it")
                break
            else:
                if debug:
                    print("Found nothing changeable in history")
                return None, None, steps
            if debug:
                print(f"Found changeable history: {cell_idx + 1} = {chosen_value} ({options_remaining})")
            st = starting_state.clone()
            if debug:
                print("Replaying history until that moment")
            new_history = []
            for hidx, (h_cidx, h_value, h_options) in enumerate(log_history[:-hidx-1]):
                if debug:
                    print(f"H{hidx} : {h_cidx + 1} = {h_value}")
                st.state[h_cidx].value = h_value
                st.state[h_cidx].options = h_options[:]
                new_history.append([h_cidx, h_value, h_options])
            if debug:
                print(f"Now we make a new choice for {cell_idx + 1}")
            cell = st.state[cell_idx]
            cell.value = options_remaining[0]
            cell.options = [o for o in options_remaining if o != cell.value]
            new_history.append([cell_idx, cell.value, cell.options])
            log_history = new_history
            if debug:
                print("NEW HISTORY:")
                print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
        elif cell is not None and cell.options:
            new_value = cell.options[0]
            cell.value = new_value
            if debug:
                print("try with", idx + 1, "=", cell.value)
                print("so now we have")
                print(st.state)
            if st.is_valid(debug=debug):
                if debug:
                    print("that's valid")
                log_history.append([idx, new_value, [o for o in cell.options if o != new_value]])
                if debug:
                    print("HISTORY NOW:")
                    print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
                continue
            if debug:
                print("invalid, remove this value and set back to EMPTY")
            st = st.clone()
            st.state[idx].options = [
                o for o in st.state[idx].options if o != new_value
            ]
            st.state[idx].value = EMPTY
            if debug:
                print("so now we are back with")
                print(st.state)
    if steps >= MAX_STEPS:
        raise RuntimeError("Reached MAX_STEPS")

    if not st.is_complete(debug=debug):
        return None, None, steps
    return st, backpropagations, steps


def old_find_solution_with_apply(running, starting_state, debug=False):
    start = time.time()
    st = starting_state.clone()
    try:
        st.apply_constraints()
    except CannotApplyConstraint:
        if debug:
            print(" " * level, "cannot apply constraints, consider this as unsolvable")
        return None, None, 0
    log_history = []
    steps = 0
    backpropagations = 0
    while steps <= MAX_STEPS and running.is_set():
        if st.is_complete(debug=debug):
            break
        if debug:
            print(st.state)
        steps += 1
        cell, idx = st.first_free_cell()
        if cell is None or not st.is_possible():
            if debug:
                print("Not possible anymore")
                print("HISTORY:")
                print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
            # Rewind history, until we find a moment where a value was fixed,
            # change that value and keep looking for solutions.
            if not log_history:
                if debug:
                    print("No history left, no solution found")
                return None, None, steps
            previous_line = st
            backpropagations += 1
            for hidx, line in enumerate(log_history[::-1]):
                cell_idx, chosen_value, options_remaining = line
                if debug:
                    print(f"We had chosen {cell_idx+1} = {chosen_value} and still had options {options_remaining}")
                if not options_remaining:
                    continue
                if debug:
                    print("We could have chosen another option, let's try it")
                break
            else:
                if debug:
                    print("Found nothing changeable in history")
                return None, None, steps
            if debug:
                print(f"Found changeable history: {cell_idx + 1} = {chosen_value} ({options_remaining})")
            st = starting_state.clone()
            if debug:
                print("Replaying history until that moment")
            new_history = []
            for hidx, (h_cidx, h_value, h_options) in enumerate(log_history[:-hidx-1]):
                if debug:
                    print(f"H{hidx} : {h_cidx + 1} = {h_value}")
                st.state[h_cidx].value = h_value
                st.state[h_cidx].options = h_options[:]
                new_history.append([h_cidx, h_value, h_options])
            if debug:
                print(f"Now we make a new choice for {cell_idx + 1}")
            cell = st.state[cell_idx]
            cell.value = options_remaining[0]
            cell.options = [o for o in options_remaining if o != cell.value]
            new_history.append([cell_idx, cell.value, cell.options])
            log_history = new_history
            if debug:
                print("NEW HISTORY:")
                print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
        elif cell is not None and cell.options:
            new_value = cell.options[0]
            cell.value = new_value
            if debug:
                print("try with", idx + 1, "=", cell.value)
                print("so now we have")
                print(st.state)
            if st.is_valid(debug=debug):
                if debug:
                    print("that's valid")
                log_history.append([idx, new_value, [o for o in cell.options if o != new_value]])
                if debug:
                    print("HISTORY NOW:")
                    print("\n".join([f"Set {l[0] + 1} = {l[1]} (options {l[2]})" for l in log_history]))
                continue
            if debug:
                print("invalid, remove this value and set back to EMPTY")
            st = st.clone()
            st.state[idx].options = [
                o for o in st.state[idx].options if o != new_value
            ]
            st.state[idx].value = EMPTY
            if debug:
                print("so now we are back with")
                print(st.state)
    if steps >= MAX_STEPS:
        raise RuntimeError("Reached MAX_STEPS")

    if not st.is_complete(debug=debug):
        return None, None, steps
    return st, backpropagations, steps

