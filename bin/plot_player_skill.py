#!/usr/bin/env python3
"""Plot per-player progression over time.

Reads aggregated stats files produced by `bin/aggregate_player_stats.dart`
and draws a matplotlib chart with one curve per player.

Two y-axis modes (`--y-axis`):

* `skill` (default) — implicit player level in cplx units, mirrors
  `Database.computePlayerLevel` in the app:

      expected   = kBase · cells^kCellsExp · exp(cplx / kCplxScale)
                         · kFailMul^failures · kNConsMul^nConstraints
      impliedCplx = kCplxScale · (ln(dur) - ln(kBase) - kCellsExp·ln(cells)
                                  - failures·ln(kFailMul)
                                  - nConstraints·ln(kNConsMul))
      skill_i    = 2 · cplx − impliedCplx

* `level` — the puzzle's category in the cognitive 6-tier classification
  (Débutant…Fou furieux), looked up from `assets/<level>.txt` by canonical
  puzzle key. Plotted as 1..6 with category labels on the y-axis. Plays
  whose puzzle is not present in any of the asset files are dropped
  (with a count printed) — typically tutorial puzzles or legacy entries
  that have since been pruned. See `docs/dev/levels.md`.

Both modes use the same EMA smoothing (default half-life = 25 plays)
and gap-break logic.

Usage:
    python3 bin/plot_player_skill.py [stats_aggregated/gle.txt ...] \
        [-o out.png] [--y-axis skill|level] [--scatter] \
        [--half-life 25] [--break-gap-days 7] \
        [--ylim a b] [--start ISO] [--end ISO] \
        [--assets-dir assets]
"""

import argparse
import math
import os
import re
import sys
from datetime import datetime

import matplotlib.dates as mdates
import matplotlib.pyplot as plt

# Constants mirror lib/getsomepuzzle/model/database.dart (v1.6.1+ fit).
K_BASE = 3.3108
K_CELLS_EXP = 0.5146
K_CPLX_SCALE = 123.82
K_FAIL_MUL = 1.1627
K_NCONS_MUL = 1.1069

LEVEL_FILES = [
    # Loaded in this order; later entries override earlier ones, so a
    # puzzle that ended up in BOTH `overfilled.txt` (legacy snapshot)
    # AND a current cognitive tier is bound to the proper tier.
    ("overfilled", 0, "Pré-rempli"),
    ("overfilled-easy", 0, "Pré-rempli"),
    ("1-easy", 1, "Débutant"),
    ("2-player", 2, "Joueur"),
    ("3-advanced", 3, "Avancé"),
    ("4-strong", 4, "Balaise"),
    ("5-expert", 5, "Expert"),
    ("6-mad", 6, "Fou furieux"),
]


def implied_cplx(dur: int, cells: int, failures: int, n_cons: int) -> float:
    return K_CPLX_SCALE * (
        math.log(dur)
        - math.log(K_BASE)
        - K_CELLS_EXP * math.log(cells)
        - failures * math.log(K_FAIL_MUL)
        - n_cons * math.log(K_NCONS_MUL)
    )


def expected_duration(cplx: int, cells: int, failures: int, n_cons: int) -> float:
    return (
        K_BASE
        * (cells ** K_CELLS_EXP)
        * math.exp(cplx / K_CPLX_SCALE)
        * (K_FAIL_MUL ** failures)
        * (K_NCONS_MUL ** n_cons)
    )


def canonical_puzzle_key(line: str) -> str:
    """Mirror of `canonicalPuzzleKey` in lib/getsomepuzzle/model/canonical.dart.

    Drops the version prefix, solution, complexity and any trailing
    `_p:<state>`. Constraints are dedup-on-string, sorted, and `TX:*`
    entries are dropped — same normalization used by the app and by
    `bin/dedup_stats.dart`.
    """
    parts = line.strip().split("_")
    start = 1 if parts and re.fullmatch(r"v\d+", parts[0]) else 0
    if len(parts) < start + 4:
        return line.strip()
    domain = parts[start]
    dimensions = parts[start + 1]
    prefill = parts[start + 2]
    constraints_field = parts[start + 3]
    seen = set()
    kept = []
    for c in constraints_field.split(";"):
        if c.startswith("TX:") or c == "TX":
            continue
        if c not in seen:
            seen.add(c)
            kept.append(c)
    kept.sort()
    return f"{domain}_{dimensions}_{prefill}_{';'.join(kept)}"


def load_puzzle_levels(assets_dir: str) -> dict:
    """Build canonical_key → level (1..6) by scanning the per-tier asset files.

    Missing files are skipped silently (a partial corpus still works).
    """
    out = {}
    for stem, lvl, _name in LEVEL_FILES:
        path = os.path.join(assets_dir, f"{stem}.txt")
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                out[canonical_puzzle_key(line)] = lvl
    return out


def parse_play(line: str):
    """Return (timestamp, skill_i, cplx, canonical_key) or None."""
    fields = line.strip().split(" ")
    if len(fields) < 4 or fields[0] == "unfinished":
        return None
    try:
        ts = datetime.fromisoformat(fields[0])
    except ValueError:
        return None
    try:
        dur = int(fields[1].rstrip("s"))
        failures = int(fields[2].rstrip("f"))
    except ValueError:
        return None
    if dur <= 0:
        dur = 1
    puzzle_line = fields[3]
    parts = puzzle_line.split("_")
    if len(parts) < 7:
        return None
    m = re.match(r"^(\d+)x(\d+)$", parts[2])
    if not m:
        return None
    cells = int(m.group(1)) * int(m.group(2))
    constraints_field = parts[4]
    n_cons = (
        len([c for c in constraints_field.split(";") if c])
        if constraints_field
        else 0
    )
    try:
        cplx = int(parts[6])
    except ValueError:
        return None
    expected = expected_duration(cplx, cells, failures, n_cons)
    clamped = min(max(dur, 1), int(expected * 10) or 1)
    skill_i = 2 * cplx - implied_cplx(clamped, cells, failures, n_cons)
    key = canonical_puzzle_key(puzzle_line)
    return ts, skill_i, cplx, key


def load_plays(path: str):
    plays = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            r = parse_play(line)
            if r is not None:
                plays.append(r)
    plays.sort(key=lambda x: x[0])
    return plays


def ema(values, half_life):
    """Causal exponentially decaying mean, half-life in samples."""
    if not values:
        return []
    decay = math.pow(0.5, 1.0 / half_life)
    out = []
    weighted = 0.0
    weight = 0.0
    for v in values:
        weighted = weighted * decay + v
        weight = weight * decay + 1.0
        out.append(weighted / weight)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="aggregated stats files")
    ap.add_argument("-o", "--output", default=None,
                    help="output PNG (default depends on --y-axis)")
    ap.add_argument("--y-axis", choices=["skill", "level"], default="skill",
                    help="metric on the y-axis: implicit skill (default) "
                         "or puzzle category (1..6, see docs/dev/levels.md)")
    ap.add_argument("--scatter", action="store_true",
                    help="overlay raw per-play points (light)")
    ap.add_argument("--half-life", type=float, default=25.0,
                    help="EMA half-life in plays (default 25)")
    ap.add_argument("--break-gap-days", type=float, default=7.0,
                    help="break the line on gaps longer than N days (0 = never)")
    ap.add_argument("--ylim", type=float, nargs=2, default=None,
                    help="y-axis bounds (defaults depend on --y-axis)")
    ap.add_argument("--start", default=None,
                    help="ISO date — drop plays before this")
    ap.add_argument("--end", default=None,
                    help="ISO date — drop plays after this")
    ap.add_argument("--assets-dir", default="assets",
                    help="directory holding 1-easy.txt..6-mad.txt")
    args = ap.parse_args()

    start = datetime.fromisoformat(args.start) if args.start else None
    end = datetime.fromisoformat(args.end) if args.end else None

    files = args.files or [
        "stats_aggregated/gle.txt",
        "stats_aggregated/jml.txt",
        "stats_aggregated/flo.txt",
    ]
    files = [f for f in files if os.path.exists(f)]
    if not files:
        print("No input files found.", file=sys.stderr)
        sys.exit(1)

    levels_by_key = {}
    if args.y_axis == "level":
        levels_by_key = load_puzzle_levels(args.assets_dir)
        if not levels_by_key:
            print(
                f"No level files found under {args.assets_dir}/. "
                f"Expected 1-easy.txt..6-mad.txt.",
                file=sys.stderr,
            )
            sys.exit(1)
        print(f"Loaded {len(levels_by_key)} classified puzzles "
              f"from {args.assets_dir}/.")

    output = args.output or (
        "stats_aggregated/level.png"
        if args.y_axis == "level"
        else "stats_aggregated/skill.png"
    )

    fig, ax = plt.subplots(figsize=(12, 6))
    colors = ["#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e"]

    for i, path in enumerate(files):
        label = os.path.splitext(os.path.basename(path))[0]
        plays = load_plays(path)
        if start is not None:
            plays = [p for p in plays if p[0] >= start]
        if end is not None:
            plays = [p for p in plays if p[0] <= end]
        if not plays:
            print(f"{path}: no usable plays in range", file=sys.stderr)
            continue

        if args.y_axis == "level":
            kept = []
            unmatched = 0
            for ts, _skill, _cplx, key in plays:
                lvl = levels_by_key.get(key)
                if lvl is None:
                    unmatched += 1
                    continue
                kept.append((ts, lvl))
            if unmatched:
                print(f"  {label}: {unmatched}/{len(plays)} plays not "
                      f"matched to any tier (legacy/tutorial puzzles)")
            if not kept:
                continue
            ts = [p[0] for p in kept]
            values = [p[1] for p in kept]
        else:
            ts = [p[0] for p in plays]
            values = [p[1] for p in plays]

        smoothed = ema(values, args.half_life)
        if args.break_gap_days > 0:
            broken_ts, broken_smooth = [ts[0]], [smoothed[0]]
            for k in range(1, len(ts)):
                gap = (ts[k] - ts[k - 1]).total_seconds() / 86400.0
                if gap > args.break_gap_days:
                    broken_ts.append(ts[k - 1])
                    broken_smooth.append(float("nan"))
                broken_ts.append(ts[k])
                broken_smooth.append(smoothed[k])
        else:
            broken_ts, broken_smooth = ts, smoothed

        color = colors[i % len(colors)]
        if args.scatter:
            ax.scatter(ts, values, s=4, alpha=0.15, color=color)
        ax.plot(broken_ts, broken_smooth,
                label=f"{label} (n={len(values)})",
                color=color, linewidth=2)
        print(
            f"{label}: {len(values)} plays, "
            f"first={ts[0].date()}, last={ts[-1].date()}, "
            f"final={smoothed[-1]:.2f}"
        )

    ax.set_xlabel("Date")
    if args.y_axis == "level":
        ax.set_title("Puzzle tier played over time")
        ax.set_ylabel("Tier (cognitive level of puzzles played)")
        # Dedup tick labels (overfilled.txt + overfilled-easy.txt share level 0).
        seen_lvl = {}
        for _stem, lvl, name in LEVEL_FILES:
            seen_lvl.setdefault(lvl, name)
        ticks = sorted(seen_lvl.keys())
        ax.set_yticks(ticks)
        ax.set_yticklabels([f"{lvl}. {seen_lvl[lvl]}" for lvl in ticks])
        if args.ylim is None:
            ax.set_ylim(-0.5, 6.5)
        else:
            ax.set_ylim(args.ylim[0], args.ylim[1])
    else:
        ax.set_title("Player skill progression over time")
        ax.set_ylabel("Skill (cplx-equivalent units)")
        ax.axhline(50, color="grey", linestyle=":", linewidth=0.8,
                   label="cohort baseline (50)")
        if args.ylim is None:
            ax.set_ylim(-50, 150)
        else:
            ax.set_ylim(args.ylim[0], args.ylim[1])

    ax.xaxis.set_major_locator(mdates.AutoDateLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d"))
    fig.autofmt_xdate()
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(output, dpi=130)
    print(f"\nSaved → {output}")


if __name__ == "__main__":
    main()
