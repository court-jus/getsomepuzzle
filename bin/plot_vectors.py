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

The points are alpha-blended (default 0.3) and the per-class centroids
are annotated so the eye finds them in a dense scatter.

Usage:
    python3 bin/plot_vectors.py [--input puzzle_vectors.csv]
                                 [--output puzzle_pca.png]
                                 [--color-by file|dominant_slug|level|complexity]
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
        choices=["file", "dominant_slug", "level", "complexity"],
        default="file",
        help="Categorical or continuous coloring scheme",
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

    if args.color_by == "complexity":
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
    ax.set_title(
        f"PCA projection of {len(rows)} puzzle vectors  "
        f"(colored by {args.color_by})"
    )
    ax.grid(True, linestyle=":", linewidth=0.5, alpha=0.5)

    fig.tight_layout()
    fig.savefig(args.output, dpi=120, bbox_inches="tight")
    sys.stderr.write(f"Wrote {args.output}\n")


if __name__ == "__main__":
    main()
