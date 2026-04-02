from ..constraints.other_solution import OtherSolutionConstraint


def find_solution(running, puzzle, level=0, debug=False):
    """Find a single solution using propagation + force + backtracking.
    Returns (solution, backtrack_steps, total_steps) for backward compatibility.
    backtrack_steps is 0 if solved without backtracking."""
    sol, steps = puzzle.solve_with_backtracking(running=running, explain=debug)
    if sol is not None:
        return sol, steps, steps
    return None, None, steps


def find_solutions(puzzle, running, max_solutions=2, debug=False):
    """Find up to max_solutions distinct solutions."""
    initial_state = puzzle.clone()
    initial_state.apply_fixed_constraints(debug=debug)
    solutions = []
    for _ in range(max_solutions):
        if not running.is_set():
            break
        sol, _, _ = find_solution(running, initial_state, debug=debug)
        if sol is None:
            break
        found_solution = [c.value for c in sol.state]
        solutions.append(found_solution)
        initial_state.constraints.append(
            OtherSolutionConstraint(solution=found_solution)
        )
    return solutions
