import argparse

from .gspengine import PuzzleGenerator
from .utils import state_to_str, export_puzzle, import_puzzle


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-l", "--load")
    parser.add_argument("-s", "--save")
    parser.add_argument("-c", "--check")
    parser.add_argument("-d", "--debug", action="store_true")
    args = parser.parse_args()
    print("AR", args)
    if args.load:
        with open(args.load, "r") as fp:
            pu = import_puzzle(fp.read())
    else:
        pg = PuzzleGenerator()
        pu = pg.generate(debug=args.debug)
    print(pu)
    print(state_to_str(pu))
    for solution in pu.find_solutions(debug=args.debug):
        print("SOLUTION", solution)

    if args.check:
        print(pu.check_solution([int(i) for i in args.check], debug=args.debug))

    if args.save:
        with open(args.save, "w") as fp:
            fp.write(export_puzzle(pu))


if __name__ == "__main__":
    main()
