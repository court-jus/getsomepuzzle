#!/usr/bin/env python3
"""2D PCA projection of the puzzle vectors produced by
`bin/vectorize_puzzles.dart`.

Reads `puzzle_vectors.csv`, z-scores the same 85 features the Dart
clustering pipeline uses (78 trace shares + 7 difficulty/structural
signals), projects to two principal components via SVD, and emits a
scatter plot.

Coloring strategies (`--color-by`):

* `file` (default) — one color per source collection
  (1-easy, 2-player, …). Best to see whether the level cascade really
  carves the corpus into separable lobes.
* `dominant_slug` — color by the slug with the highest share in the
  trace. Shows which constraint families occupy which neighbourhoods.
* `level` — color by the ordinal level (beginner=0…undetermined=8).
* `complexity` — continuous colormap on `complexity`. Shows the
  difficulty gradient.
* `labeled` — binary highlight: puzzles whose `canonical_key` matches
  `--label-regex` (optionally filtered by `--even-only` for even grid
  dimensions) are drawn in red; the rest in translucent grey.
  A separation report is printed to stderr: count, top-5 discriminating
  features, and how well the two groups separate on PC1/PC2.

The points are alpha-blended (default 0.3) and the per-class centroids
are annotated so the eye finds them in a dense scatter.

Usage:
    python3 bin/plot_vectors.py [--input puzzle_vectors.csv]
                                 [--output puzzle_pca.png]
                                 [--color-by file|dominant_slug|level|complexity|labeled]
                                 [--label-regex REGEX] [--even-only]
                                 [--sample N] [--alpha A] [--seed S]
"""

import argparse
import csv
import math
import os
import sys
from collections import defaultdict

import matplotlib.pyplot as plt
import numpy as np

# Mirror the slug / tier definitions used by `bin/vectorize_puzzles.dart`
# and `bin/cluster_puzzles.dart`. Keeps the PCA input in lock-step with
# the Dart pipeline so the picture matches what the clusterer sees.
SLUGS = ["CC", "CX", "DF", "EY", "FM", "GC", "GS", "LT", "NC", "PA", "QA", "SH", "SY"]
TIERS = [0, 1, 2, 3, 4, 5]

EXTRA_FEATURES = [
    "complexity",
    "n_force_rounds",
    "max_force_depth",
    "avg_move_complexity",
    "distinct_constraints_used",
    "n_constraints",
    "cells",
    "prefill_ratio",
]


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--input", default="puzzle_vectors.csv", help="CSV from vectorize_puzzles.dart")
    p.add_argument("--output", default="puzzle_pca.png", help="Output PNG path")
    p.add_argument(
        "--color-by",
        choices=["file", "dominant_slug", "level", "complexity", "labeled"],
        default="file",
        help="Categorical or continuous coloring scheme",
    )
    p.add_argument(
        "--label-regex",
        default=r"SH:(11\.11|22\.22)",
        help="Regex matched against canonical_key to select the labeled group (used with --color-by labeled)",
    )
    p.add_argument(
        "--even-only",
        action="store_true",
        help="With --color-by labeled: restrict the label to puzzles whose width AND height are both even",
    )
    p.add_argument("--sample", type=int, default=None, help="Random sub-sample size (for faster plots / less crowding)")
    p.add_argument("--seed", type=int, default=42, help="RNG seed for --sample")
    p.add_argument("--alpha", type=float, default=0.3, help="Marker alpha (default 0.3)")
    p.add_argument("--size", type=float, default=6.0, help="Marker size (default 6)")
    p.add_argument("--figsize", nargs=2, type=float, default=(11, 9), help="Figure size in inches")
    p.add_argument("--no-centroids", action="store_true", help="Skip per-class centroid annotations")
    return p.parse_args()


def feature_column_names():
    """Same column ordering as the Dart side: 78 share_* then the 8 extras."""
    cols = []
    for s in SLUGS:
        for t in TIERS:
            cols.append(f"share_{s}_t{t}")
    cols.extend(EXTRA_FEATURES)
    return cols


def load_rows(csv_path):
    """Read the CSV. Returns: header, list of dicts (str→str)."""
    with open(csv_path, newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        rows = [dict(zip(header, r)) for r in reader if r]
    return header, rows


def dominant_slug(row):
    """Pick the slug with the largest summed share across its tiers.
    Mirrors the bucketing step in `bin/cluster_puzzles.dart`.
    """
    best_slug = SLUGS[0]
    best_sum = -1.0
    for s in SLUGS:
        total = 0.0
        for t in TIERS:
            v = row.get(f"share_{s}_t{t}", "0")
            try:
                total += float(v)
            except ValueError:
                pass
        if total > best_sum:
            best_sum = total
            best_slug = s
    return best_slug


def build_matrix(rows, feature_cols):
    """Stack feature values into a (n_samples, n_features) float array."""
    n = len(rows)
    m = len(feature_cols)
    X = np.zeros((n, m), dtype=np.float64)
    for i, row in enumerate(rows):
        for k, col in enumerate(feature_cols):
            try:
                X[i, k] = float(row.get(col, 0) or 0)
            except ValueError:
                X[i, k] = 0.0
    return X


def z_score(X, z_clip=5.0):
    """Center each column, divide by std, clip at ±z_clip. Mirrors the
    in-Dart normalization so the picture matches the clusterer.
    Columns with std=0 (constant) are zeroed.
    """
    mean = X.mean(axis=0)
    std = X.std(axis=0)
    out = np.zeros_like(X)
    nonzero = std > 1e-12
    out[:, nonzero] = (X[:, nonzero] - mean[nonzero]) / std[nonzero]
    np.clip(out, -z_clip, z_clip, out=out)
    return out


def pca_2d(X):
    """Compute the first two principal components via SVD on the
    centered matrix. Returns: 2D coords (n_samples × 2) and the
    explained-variance ratio for the two components.
    """
    Xc = X - X.mean(axis=0)
    # Economy SVD: U is (n × k), S (k,), Vt (k × m) with k = min(n, m).
    # X = U · diag(S) · Vt; PCA scores = U · diag(S) = X · Vt.T
    # For 26k × 85, full_matrices=False is fast and memory-safe.
    U, S, _ = np.linalg.svd(Xc, full_matrices=False)
    coords = U[:, :2] * S[:2]
    total_var = (S ** 2).sum()
    var_ratio = (S[:2] ** 2 / total_var) if total_var > 0 else np.zeros(2)
    return coords, var_ratio


def color_palette(n):
    """Return n visually distinct colors. Uses tab20 + tab20b cycling for
    up to 40 categories — comfortably more than the 13 slugs / 8 files
    / 9 levels we expect.
    """
    base = plt.get_cmap("tab20").colors + plt.get_cmap("tab20b").colors
    return [base[i % len(base)] for i in range(n)]


def build_labeled_mask(rows, label_regex, even_only):
    """Return a boolean array: True where canonical_key matches label_regex.
    If even_only, also require width and height to both be even.
    """
    import re
    pattern = re.compile(label_regex)
    mask = np.zeros(len(rows), dtype=bool)
    for i, row in enumerate(rows):
        key = row.get("canonical_key", "")
        if not pattern.search(key):
            continue
        if even_only:
            try:
                w = int(row.get("width", 0) or 0)
                h = int(row.get("height", 0) or 0)
            except ValueError:
                continue
            if w % 2 != 0 or h % 2 != 0:
                continue
        mask[i] = True
    return mask


def report_separation(mask, Xn, feature_cols, coords):
    """Print a cluster separation report to stderr."""
    n_labeled = mask.sum()
    n_total = len(mask)
    sys.stderr.write(f"\n  Labeled: {n_labeled} / {n_total} ({100*n_labeled/n_total:.1f}%)\n")

    if n_labeled == 0:
        sys.stderr.write("  No labeled puzzles found — check --label-regex and --even-only.\n")
        return

    # Mean z-score difference per feature.
    diff = Xn[mask].mean(axis=0) - Xn[~mask].mean(axis=0)
    ranked = sorted(enumerate(feature_cols), key=lambda x: abs(diff[x[0]]), reverse=True)
    sys.stderr.write("  Top-10 discriminating features (mean z-score labeled - rest):\n")
    for rank, (fi, fname) in enumerate(ranked[:10], 1):
        sign = "+" if diff[fi] >= 0 else ""
        sys.stderr.write(f"    {rank:2d}. {fname:<35s}  {sign}{diff[fi]:.3f}\n")

    # PCA separation.
    pc1_labeled = coords[mask, 0]
    pc1_rest = coords[~mask, 0]
    pc2_labeled = coords[mask, 1]
    pc2_rest = coords[~mask, 1]
    sys.stderr.write(
        f"\n  PC1 centroid — labeled: {pc1_labeled.mean():+.3f}  rest: {pc1_rest.mean():+.3f}\n"
        f"  PC2 centroid — labeled: {pc2_labeled.mean():+.3f}  rest: {pc2_rest.mean():+.3f}\n"
    )


def main():
    args = parse_args()

    if not os.path.exists(args.input):
        sys.stderr.write(f"CSV not found: {args.input}\n")
        sys.exit(1)

    header, rows = load_rows(args.input)
    sys.stderr.write(f"  {len(rows)} rows loaded from {args.input}\n")

    if args.sample is not None and args.sample < len(rows):
        rng = np.random.default_rng(args.seed)
        idx = rng.choice(len(rows), size=args.sample, replace=False)
        rows = [rows[i] for i in idx]
        sys.stderr.write(f"  Sampled {len(rows)} rows (seed={args.seed})\n")

    feature_cols = feature_column_names()
    missing = [c for c in feature_cols if c not in header]
    if missing:
        sys.stderr.write(f"Missing columns: {missing}\n")
        sys.exit(1)

    X = build_matrix(rows, feature_cols)
    Xn = z_score(X)
    coords, var_ratio = pca_2d(Xn)
    sys.stderr.write(
        f"  PC1 = {var_ratio[0]*100:.1f}%, PC2 = {var_ratio[1]*100:.1f}% "
        f"of total variance\n"
    )

    fig, ax = plt.subplots(figsize=tuple(args.figsize))

    if args.color_by == "labeled":
        mask = build_labeled_mask(rows, args.label_regex, args.even_only)
        report_separation(mask, Xn, feature_cols, coords)

        # Background: all unlabeled in grey.
        rest_idx = np.where(~mask)[0]
        ax.scatter(
            coords[rest_idx, 0], coords[rest_idx, 1],
            c="lightgrey", s=args.size, alpha=max(args.alpha * 0.6, 0.05),
            linewidths=0, label=f"other ({(~mask).sum()})",
        )
        # Foreground: labeled in red with cross marker.
        lab_idx = np.where(mask)[0]
        if len(lab_idx):
            ax.scatter(
                coords[lab_idx, 0], coords[lab_idx, 1],
                c="crimson", marker="x", s=args.size * 4,
                alpha=min(args.alpha * 3, 1.0), linewidths=0.8,
                label=f"labeled ({mask.sum()})",
                zorder=5,
            )
        ax.legend(loc="upper right", fontsize=9, frameon=True)
        if not args.no_centroids and len(lab_idx):
            cx = coords[lab_idx, 0].mean()
            cy = coords[lab_idx, 1].mean()
            ax.annotate(
                "cluster", (cx, cy),
                fontsize=9, fontweight="bold", color="crimson",
                ha="center", va="bottom", xytext=(0, 8), textcoords="offset points",
            )

    elif args.color_by == "complexity":
        # Continuous scalar coloring — colormap with colorbar.
        vals = np.array([float(r.get("complexity", 0) or 0) for r in rows])
        sc = ax.scatter(
            coords[:, 0], coords[:, 1], c=vals, cmap="viridis",
            s=args.size, alpha=args.alpha, linewidths=0,
        )
        fig.colorbar(sc, ax=ax, label="complexity (cached 0-100)")
    else:
        # Categorical coloring.
        if args.color_by == "file":
            labels = [os.path.basename(r.get("file", "?")).replace(".txt", "") for r in rows]
        elif args.color_by == "dominant_slug":
            labels = [dominant_slug(r) for r in rows]
        elif args.color_by == "level":
            labels = [r.get("level", "?") for r in rows]
        else:
            labels = ["?" for _ in rows]
        unique = sorted(set(labels))
        palette = color_palette(len(unique))
        color_by_label = dict(zip(unique, palette))

        # Plot one scatter per class so the legend picks up nicely.
        idx_by_label = defaultdict(list)
        for i, lab in enumerate(labels):
            idx_by_label[lab].append(i)
        for lab in unique:
            ii = idx_by_label[lab]
            ax.scatter(
                coords[ii, 0], coords[ii, 1],
                c=[color_by_label[lab]] * len(ii),
                s=args.size, alpha=args.alpha, linewidths=0,
                label=f"{lab} ({len(ii)})",
            )
        ax.legend(
            loc="center left", bbox_to_anchor=(1.02, 0.5),
            fontsize=8, frameon=False, markerscale=2,
        )

        # Per-class centroid annotations — readable orientation in a
        # dense scatter where the eye otherwise drowns in points.
        if not args.no_centroids:
            for lab in unique:
                ii = idx_by_label[lab]
                cx = coords[ii, 0].mean()
                cy = coords[ii, 1].mean()
                ax.annotate(
                    lab, (cx, cy),
                    fontsize=9, fontweight="bold",
                    ha="center", va="center",
                    bbox=dict(
                        boxstyle="round,pad=0.2",
                        facecolor="white", alpha=0.7, edgecolor="black", linewidth=0.5,
                    ),
                )

    ax.set_xlabel(f"PC1 ({var_ratio[0]*100:.1f}% variance)")
    ax.set_ylabel(f"PC2 ({var_ratio[1]*100:.1f}% variance)")
    if args.color_by == "labeled":
        title_suffix = f"labeled: {args.label_regex}" + (" (even dims)" if args.even_only else "")
    else:
        title_suffix = f"colored by {args.color_by}"
    ax.set_title(
        f"PCA projection of {len(rows)} puzzle vectors  "
        f"({title_suffix})"
    )
    ax.grid(True, linestyle=":", linewidth=0.5, alpha=0.5)

    fig.tight_layout()
    fig.savefig(args.output, dpi=120, bbox_inches="tight")
    sys.stderr.write(f"Wrote {args.output}\n")


if __name__ == "__main__":
    main()
