import argparse
import queue
import concurrent.futures
import random
from pathlib import Path
import pprint

from .generator.puzzle_generator import generate_one
from .solver.puzzle_solver import find_solutions
from .utils import FakeEvent, state_to_str, export_puzzle, import_puzzle, line_export, compute_level


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-l", "--load")
    parser.add_argument("-s", "--save")
    parser.add_argument("-c", "--check")
    parser.add_argument("-d", "--debug", action="count", default=0)
    parser.add_argument("-m", "--max", type=int, default=10)
    parser.add_argument("-W", "--width", type=int, default=None)
    parser.add_argument("-H", "--height", type=int, default=None)
    parser.add_argument("-A", "--alternate", action="store_true", default=False)
    parser.add_argument("-v", "--value")
    parser.add_argument("-n", "--number", type=int, default = 1)
    parser.add_argument("--read-stats")
    args = parser.parse_args()

    if args.read_stats:
        path = Path(args.read_stats)
        result = {}
        for file in path.iterdir():
            if file.is_dir():
                continue
            if file.name == "sorted_puzzles.txt":
                continue
            data = file.read_text()
            for line in data.split("\n"):
                if not line:
                    continue
                timestamp, duration, _, failures, puzzle = line.split(" ")
                duration = int(duration.replace("s", ""))
                failures = int(failures.replace("f", ""))
                if puzzle not in result:
                    result[puzzle] = { "total": 0, "duration": 0, "failures": 0, "level": 0, "puzzle": puzzle }
                result[puzzle]["total"] += 1
                result[puzzle]["duration"] += duration
                result[puzzle]["failures"] += failures
                result[puzzle]["level"] = compute_level(**result[puzzle])
        data = sorted(
            result.values(),
            key=lambda stat: stat["level"]
        )
        result_path = path / "sorted_puzzles.txt"
        result_path.write_text("\n".join(stat["puzzle"] for stat in data))
        return

    if args.load:
        with open(args.load, "r") as fp:
            pu = import_puzzle(fp.read())
    elif args.number > 1:
        # Generate a bunch of puzzles
        running = FakeEvent()
        futures = []
        tasks = [
            (running,
            args.width if args.width is not None else random.randint(4, 6),
            args.height if args.height is not None else random.randint(4, 7))
            for _ in range(args.number)
        ]
        path = Path("getsomepuzzle") / "resources" / "puzzles3.txt"
        print("Will write to", path)
        with concurrent.futures.ProcessPoolExecutor() as executor:
            print("executor ready")
            for result in executor.map(generate_one, tasks):
                line = line_export(result)
                with open(path, "a") as fp:
                    fp.write(line + "\n")
    else:
        pu = None
        request_queue = queue.Queue()
        response_queue = queue.Queue()
        running = FakeEvent()
        pu = generate_one((
            running,
            args.width if args.width is not None else random.randint(3, 6),
            args.height if args.height is not None else random.randint(3, 7)
        ))
    if args.number == 1 and not args.alternate:
        pu.remove_useless_rules(debug=args.debug > 1)
        print(pu)
        print(state_to_str(pu))
        found_solutions = find_solutions(pu, FakeEvent(), debug=args.debug > 2)
        print("FOUND", len(found_solutions), "solutions")
        for solution in found_solutions:
            print("SOLUTION", solution)

    if args.check:
        print(pu.check_solution([int(i) for i in args.check], debug=args.debug))

    if args.value:
        idx, val = map(int, args.value.split(":"))
        pu.state[idx - 1].value = val
        pu.state[idx - 1].options = []
        print(state_to_str(pu))
        for constraint in pu.constraints:
            print("Check constraint", constraint)
            print(constraint.check(pu, debug=True))

    if args.save:
        with open(args.save, "w") as fp:
            fp.write(export_puzzle(pu))


if __name__ == "__main__":
    main()
