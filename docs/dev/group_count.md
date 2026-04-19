# WIP: Group Count constraint

New constraint type "Group Count" (slug GC).

Serialized as `GC:2.5` (slug:color.value), it means that the solution contains
"value" groups of color "color".

The example above means there are 5 white groups.

This constraint is represented in the top bar, with the ForbiddenMotif, Quantity, ...
widgets.

Visually, it contains a link icon (to represent the fact that the cells that form
the group are connected), and the numeric value, with a text color matching the
constraint's color.

---

## Implementation Plan

### 1. Create constraint class (`lib/getsomepuzzle/constraints/group_count.dart`)

- Extend `Constraint` directly (not `CellsCentricConstraint` as it doesn't target specific cells)
- Properties:
  - `int color` - the cell value to count groups for
  - `int count` - the required number of groups
- Constructor parses `GC:2.5` -> `color=2`, `count=5`
- Implement `verify(Puzzle)`: use `getGroups()` and filter by color
- Implement `apply(Puzzle)`: deduction logic is **limited** because the number of groups can change as cells are filled
  - The only safe deductions can be made when the groups are bordered and cannot grow or if they are separated
    from each other by the opposite color and cannot merge.
- Implement `generateAllParameters(width, height, domain)`:
  - count range: 1 to `ceil(width * height / 2)` (worst case: alternating pattern)
  - Generate all color.count pairs for each color in domain
- Implement `serialize()` -> `'GC:$color.$count'`
- Implement `toHuman()` -> `'$count groups of color $color'`

### 2. Register constraint (`lib/getsomepuzzle/constraints/registry.dart`)

- Import `group_count.dart`
- Add entry to `constraintRegistry`:
  ```dart
  (slug: 'GC', label: 'Group count', fromParams: GroupCountConstraint.new),
  ```

### 3. Create widget (`lib/widgets/group_count.dart`)

- Similar structure to `QuantityWidget`
- Visual: link icon + numeric value
- Use `Icons.link` or custom chain icon for the "connected groups" concept
- Text color matches constraint's color (1=black, 2=white)
- Border color: green if valid, deepOrange if invalid, highlightColor if highlighted

### 4. Integrate into puzzle top bar (`lib/widgets/puzzle.dart`)

- Import `group_count.dart`
- Add case in constraint rendering around line 223 (near `QuantityWidget`)
- Pass `cellSize`, `constraint`, and `actualGroupCount` to `GroupCountWidget`
- Calculate `actualGroupCount` at puzzle level (similar to `QuantityConstraint`):
  ```dart
  actualGroupCount: getGroups(widget.currentPuzzle)
      .where((grp) => widget.currentPuzzle.cellValues[grp.first] == constraint.color)
      .length,
  ```
  Note: `getGroups()` only returns groups of filled cells (non-zero), each group contains cells of the same color

### 5. Integrate into create page (`lib/widgets/create_page.dart`)

- Add dialog to create `GC` constraint
- Similar to `_showForbiddenMotifDialog()` or quantity selector
- Allow selecting color (1 or 2) and group count (1 to max possible)

### 6. Add localization strings (`lib/l10n/`)

- Add entry for constraint label in each ARB file
- e.g., `"constraintGroupCount": "Group count"` in en, es, fr

### 7. Add test cases (`test/constraints_test.dart`)

- Test `verify()`:
  - Returns true when group count matches
  - Returns false when group count doesn't match
  - Returns true when incomplete but count <= target
- Test `apply()`:
  - Correct deduction when count reached
  - Correct impossibility when exceeded
- Test `generateAllParameters()` produces valid combinations

---

## Files to modify

1. **Create**: `lib/getsomepuzzle/constraints/group_count.dart`
2. **Create**: `lib/widgets/group_count.dart`
3. **Modify**: `lib/getsomepuzzle/constraints/registry.dart`
4. **Modify**: `lib/widgets/puzzle.dart`
5. **Modify**: `lib/widgets/create_page.dart`
6. **Modify**: `lib/l10n/app_en.arb` (+ es, fr)
7. **Modify**: `test/constraints_test.dart`