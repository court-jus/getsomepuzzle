# Adapt to player

The idea behind this feature is to select puzzles that match the player's level and preferences.

## Core Concept: Difficulty-Based Adaptation

**Phase 1: Functional Workflow** — First implement difficulty-based matching. Other dimensions (constraint preferences, grid size) to follow.

### Player Level Computation

- **Source**: History-based (performance on recent puzzles)
- **Method**: Decay-weighted average over last 50 completed puzzles
- **Weighting**: More recent puzzles have higher weight (e.g., newest = 1.0, oldest = 0.5 with exponential decay)
- **Metrics used**: Completion time, error rate, hints used

### Puzzle Difficulty

- **Source**: Already available — `PuzzleData.cplx` (range 0-100)
- **Stored in**: Puzzle file (attributes field)

### Workflow

1. Compute player's skill level from history (decay-weighted)
2. When player requests a puzzle, select from pool where puzzle difficulty ≈ player level
3. Optionally: offer slight spread (current ± 1-2 levels) for variety

## Future Enhancements

After the difficulty-based workflow is functional:

- **Constraint preferences**: Adapt based on constraint types the player solves well / struggles with
- **Grid size preferences**: Small grids (< 5x5), medium (5-10), large (> 10x10)
- **Session dynamics**: During-play suggestions if puzzle is too easy/hard
- **Collection building**: Auto-build personalized playlist based on history

## Implementation Notes

- Difficulty rating may need to be computed for existing puzzles (see generator output or solver metrics)
- Consider a "confidence" metric to know how certain we are about player's level
- Player can override with manual difficulty selection if they want different puzzles
