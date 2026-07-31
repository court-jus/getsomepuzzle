---
name: find-puzzle
description: Find puzzles in the on-disk v2 corpus matching natural-language
  criteria, e.g. "give me a puzzle with a maximum size of 5x5 that contains a
  FM and a IM constraint but no GC constraint". Use when the user asks for "a
  puzzle", "a puzzle with...", "find a puzzle that...", "show me puzzles
  with/without...". Runs "dart run bin/query_corpus.dart --playlist N" with
  the translated filters and prints the matching v2 lines.
---

# Find Puzzle

Retrieve puzzle lines from the v2 corpus (`assets/*.txt`) matching the user's
natural-language criteria, using `bin/query_corpus.dart` in `--playlist`
mode.

## Quick find

Parse the user's request into flags and run:

```bash
dart run bin/query_corpus.dart --playlist <N> <flags>
```

- `--playlist <N>`: how many puzzles the user wants (default **1** for "a
  puzzle", use the requested count for "3 puzzles", "a few", etc.).
- `--playlist` is mutually exclusive with `--group-by`/`--cross`/`--buckets`
  — those are corpus-statistics modes, not retrieval, and are out of scope
  for this skill.

Print the raw v2 lines to stdout **only** — do not decode, summarise, or
solve them unless the user explicitly asks afterwards (then point to the
`decode-puzzle` / `solve-puzzle` skills).

The script also prints scan/filter stats to stderr (scanned files, total
puzzles, filtered count, active filters) — leave that as-is; it is useful
context for the user.

## Natural language → flags

Extract every filter from the user's phrasing. Slugs are **case-sensitive,
uppercase two-letter codes** (e.g. `FM`, not `fm`).

| User says... | Flag(s) |
|---|---|
| contains / has / with FM, IM, PA | `--include-slug FM --include-slug IM --include-slug PA` (repeatable, AND) |
| without / no / doesn't contain GC, SH | `--exclude-slug GC --exclude-slug SH` (repeatable) |
| at least N constraints / minimum N types | `--min-ntypes N` |
| at most N constraints / maximum N types | `--max-ntypes N` |
| exactly N constraints / N types | `--ntypes N` |
| max size N×M / up to N×M / no bigger than N×M | `--max-area N*M` (area = width × height) |
| min size N×M / at least N×M | `--min-area N*M` |
| width N | `--width N` (repeatable = OR) |
| height M | `--height M` (repeatable = OR) |
| 2 colours / black-white / domain 2 | `--domain 2` |
| 3 colours / domain 3 | `--domain 3` |
| include rejects / all files / any file | `--in all` |
| from a specific file | `--in assets/<file>.txt` |

Notes:

- Size phrasing "maximum size of 5×5" → `--max-area 25`. "Minimum 4×4" →
  `--min-area 16`. For exact orientations use `--width` / `--height`.
- `--include-slug` entries are ANDed: `FM` + `IM` means the puzzle must
  contain **both**.
- Domain (colour count) is 2 or 3 in the corpus.
- The default scanned set is the six published difficulty files
  (`assets/1-easy.txt` … `assets/6-mad.txt`); only add `--in` when the user
  asks for rejects or a specific file.

## Constraint slug reference

The corpus tracks 21 constraint slugs. Full meanings and parameters live in
the `decode-puzzle` skill's slug reference; short glosses for recognition:

| Slug | Meaning |
|---|---|
| PA | Parity — equal colour counts on a line side |
| RC / CC | Row / column count — exact N of colour C in a line |
| RT / CT | Row / column transitions — exact number of colour changes |
| JR / JC | Row / column majority — one colour outnumbers the other |
| FM | Forbidden motif — a pattern must not appear |
| GS | Group size — a connected group must have exactly N cells |
| LT | Letter group — a letter-shaped connected group of N cells |
| QA | Quantity — exactly N cells of a colour in the whole grid |
| SY | Symmetry — two cells mirror each other |
| DF | Different from — a cell differs from its neighbours |
| SH | Shape — a shape must appear somewhere in the grid |
| CH | Chain — a chain connecting two sides |
| GC | Group count — exactly N connected groups of a colour |
| MJ | Majority (zone) — a region has more of one colour |
| NC | Neighbour count — a cell has exactly N neighbours of a colour |
| EY | Eyes — a fixed pattern of N cells of a colour |
| IM | Implication — one cell's colour forces another's |
| BB | Bounding box — a colour's cells fit in an N×M box |

The same slugs appear in user requests; map them verbatim.

## Edge cases

- **No matches** — stderr shows `After filters: 0`. Tell the user no puzzle
  matches and suggest relaxing a filter (e.g. drop an include, raise the
  size cap).
- **Fewer than requested** — the script warns on stderr and prints
  everything that does match. Report the shortfall to the user.
- **Unknown slug in the query** — the script will simply filter everything
  out; if the user mentions a code not in the reference above, flag it as
  unknown rather than silently passing it through.

## Example

User: "Give me a puzzle with a maximum size of 5x5 that contains at least a
FM constraint and a IM constraint but no GC constraint"

```bash
dart run bin/query_corpus.dart --playlist 1 \
  --max-area 25 --include-slug FM --include-slug IM --exclude-slug GC
```

Print the returned v2 line(s) verbatim.

## Key files

| File | Purpose |
|------|---------|
| `bin/query_corpus.dart` | The read-only query tool; `--playlist` prints random matching v2 lines |
| `assets/*.txt` | The v2 corpus files scanned by the script |
| `lib/getsomepuzzle/constraints/families.dart` | Slug taxonomy used by the script's `composition` axis |
| `docs/dev/collection_management.md` | Corpus management doc with more query_corpus examples |
