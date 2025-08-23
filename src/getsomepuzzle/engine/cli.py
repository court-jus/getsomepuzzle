import argparse
import threading
import queue
import time

from .generator.puzzle_generator import generate_one
from .utils import state_to_str, export_puzzle, import_puzzle
from .constants import DEFAULT_SIZE


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-l", "--load")
    parser.add_argument("-s", "--save")
    parser.add_argument("-c", "--check")
    parser.add_argument("-d", "--debug", action="count", default=0)
    parser.add_argument("-m", "--max", type=int, default=10)
    parser.add_argument("-W", "--width", type=int, default=DEFAULT_SIZE)
    parser.add_argument("-H", "--height", type=int, default=DEFAULT_SIZE)
    parser.add_argument("-A", "--alternate", action="store_true", default=False)
    parser.add_argument("-v", "--value")
    args = parser.parse_args()
    print("AR", args)
    if args.load:
        with open(args.load, "r") as fp:
            pu = import_puzzle(fp.read())
    else:
        pu = None
        request_queue = queue.Queue()
        response_queue = queue.Queue()
        running = threading.Event()
        running.set()
        pu = generate_one(running, width=args.width, height=args.height)
    print(pu)
    print(state_to_str(pu))
    if not args.alternate:
        pu.remove_useless_rules(debug=args.debug > 1)
        print(pu)
        print(state_to_str(pu))
        found_solutions = pu.find_solutions(debug=args.debug > 2)
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
