# Same Size Constraint

The Same Size constraint (`SZ`) marks at least two cells with the same card-suit
symbol. Every marked cell must belong to a different connected same-colour group;
all of those groups must have the same size in the solved puzzle.

The four symbols are heart (`H`, `♥`), diamond (`D`, `♦`), spade (`S`, `♠`),
and club (`C`, `♣`). Constraints with the same symbol are aggregated by
`Puzzle.addConstraint`, so a puzzle has at most one `SameSize` instance per
symbol.

`SZ` is colour-agnostic and belongs to the `group-topology` family.

## Syntax

`SZ:symbol.idx.idx...`, for example `SZ:H.2.11`. Indices are zero-based in the
serialized v2 line. A generated constraint starts with two distinct cells;
additional constraints carrying the same symbol merge their indices.

## Semantics

### verify

The constraint collects the existing groups containing marked cells and rejects
the state immediately if two marked cells are already in the same group. Free
marked cells are ignored while the puzzle is incomplete because they do not
belong to a group yet. One existing group can still be valid when the other
marked cells are free; once multiple marked groups exist, their sizes must
match in a complete puzzle.

### apply

`SameSize.apply` first prunes a free cell's colour when that cell would merge
two marked groups of the same colour, or when a free marked cell would join an
existing marked group. It then uses the largest currently relevant group as
the target size. For each smaller relevant group, it delegates to a temporary
`GroupSize` constraint, then retags the resulting move to the `SZ` instance.
This reuses the existing Group Size growth rules: forced exits, overshoot
pruning, reachability articulation, and impossible enclosed groups.

Marked cells that are still free do not have an existing group to grow and are
left for later propagation.


### isCompleteFor

The constraint is complete (and is greyed out) only when every marked cell is
coloured, every marked cell belongs to a distinct group, all relevant groups
have equal size, and no relevant group has a free neighbour that can still
take its colour.

## Display

`SameSizeWidget` renders the suit glyph at approximately one third of the cell
size, with a margin from the bottom-right corner. The widget is routed through
`constraintToFlutter` and the shared UI registry, so the same indicator appears
in the editor, onboarding, Learning, help catalogue, and exported icon previews.

## Integration

- Model: `lib/getsomepuzzle/constraints/same_size.dart`
- Engine registry: `lib/getsomepuzzle/constraints/registry.dart`
- Aggregation: `Puzzle.addConstraint` and `Puzzle.prependConstraint`
- Widget: `lib/widgets/constraints/same_size.dart`
- Editor picker: `showSameSizeDialog` plus the multi-cell selection mode
- Localized name/help: `constraintSameSize` and `constraintExplainSZ`
