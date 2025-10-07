import sys

def clear():
    sys.stdout.write("\033[2J")

def write_at(x, y, text, clear_line=True, flush=False):
    to_write = f"\033[{y};{x}H"  # Go to position
    if clear_line:
        to_write += f"\033[2K"  # Clear line
    to_write += text
    sys.stdout.write(to_write)
    if flush:
        sys.stdout.flush()