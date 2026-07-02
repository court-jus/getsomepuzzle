# PDCG — next steps

## ✅ Priority 1 — Pure seed-only (remove preFillRegular)

- [x] Replace the full-grid `preFillRegular()` call with seed-only
      cell placement (random colours, centre-biased)
- [x] After seed placement, run `solve()` once to get `cachedSolution`
- [x] Remove `solvedValues` parameter from `_enumerateConstraintsForCellPdcg`
      — derive NC/RC/CC/QA/GC parameters from `cachedSolution` instead
- [x] Update `cachedSolution` after each accepted constraint via
      `solve()` on the clone (already done)
- [x] Verify: `preFillRegular` import stays — still used by classic path
      (line 572), no removal needed
- [x] Test: `dart analyze` clean, `dart run bin/generate.dart -n 1 --strategy pdcg`
      produces a valid puzzle, all 13 existing tests pass

## Priority 2 — Remove backing solution from parameter generation

- [x] Rename `solution` → `referenceSolution` in
      `_enumerateConstraintsForCellPdcg` and update all 14 internal
      references
- [x] `cachedSolution` non-null at call sites via `!` assertion (guarded
      by `acceptedCount > 0` and initial seed-set path)
- [x] Post-processing fill in `_generateOnePdcg`: gracefully skip cells
      that are still `CellValue.free` in `cachedSolution` instead of
      referencing the old `solvedValues` (line 1858: `if (v != CellValue.free)`)

## ✅ Priority 3 — 3-colour domain

- [x] Remove the `if (domain.length > 2)` early reject
- [x] Verify NC/RC/CC parameter generation handles 3 colours
      (the existing code already iterates `for (final cv in domain)`)
- [x] Verify DF: `solution[cellIdx] != solution[neighbour]` still works
      (it does — works for any colour pair)
- [x] Verify EY/PA/GS/SY: these are colour-agnostic (PA counts per
      colour, GS tracks group size, SY mirrors values)
- [x] Verify QA/GC: iterate `for (final cv in domain)` — already correct
- [ ] Test: generate 50 puzzles with 3-colour domain (deferred — needs P4 slugs first)

## ✅ Priority 4 — Exponential parameter space (full slug support)

- [x] Add support for FM via `generateAllParameters` + `verify` against
      `_puzzleFromSolution(referenceSolution)`
- [x] Add support for LT via adjacency-based pairs sharing a concrete
      colour in `referenceSolution`
- [x] Add support for BB via `generateAllParameters` + `verify` against
      `_puzzleFromSolution(referenceSolution)`
- [x] Add FM, LT, BB to default `allowedSlugs` and `slugPriority` for
      the PDCG round-robin
- [ ] Add support for SH (shape): requires painting the shape motif as
      readonly seed cells (reuse from `preFillSh` infrastructure)
- [ ] Add support for CH, IM, MJ, RT, CT: deferred — most require
      domain > 2 or expensive `generateAllParameters` iteration
- [ ] Test: generate 50 puzzles with 3-colour domain (deferred — needs
      more slug support first)

## ✅ Priority 5 — Gentle force (Tier 2)

- [x] `_forceCellPdcg` helper tests each domain value on target cell
      via clone → propagate, returns the single survivor
- [x] `pdcgForceDepth` field in `GeneratorConfig` (default 1)
- [x] Force step applies `SetValue` + `readonly` on the target cell
- [x] `cachedSolution` updated via `solve()` on a clone after force
- [x] Only fires when propagation plateaus (`!accepted`)
- [x] Test: force-produced puzzles pass the normal generation pipeline

## ✅ Priority 6 — Equilibrium integration

- [x] `slugDeficitScores` already in `GeneratorConfig`; PDCG path now
      reads `config.slugDeficitScores` and sorts slugs by deficit
- [x] When deficits are available, most under-represented slugs come
      first (tie-break by static priority); when absent, falls back to
      the original round-robin
- [x] Added `ProfileCategory.pdcg` to equilibrium, `kTargetProfile`
      (classic 0.78 / pdcg 0.02), `generationBucket()`, and
      `detectPuzzleProfile` marqueur detection
- [x] `_ResolvedTarget` carries optional `GenerationStrategy?`;
      `ProfileCategory.pdcg` sets it to `GenerationStrategy.pdcg`
- [x] Per-attempt config uses `attemptStrategy ?? params.strategy` so
      the equilibrium can dynamically route through PDCG
- [x] `_resolveScenario` reports `'pdcg'` when the strategy override is
      active
- [ ] Test: generate 500 puzzles with equilibrium ON, verify corpus
      distribution is balanced (large-scale; manual CLI run)

## Priority 7 — Scalability (30×20)

- [ ] Benchmark generation time per size: 10×10, 15×15, 20×20, 30×20
- [ ] Profile hot spots: `clone()` vs `propagateToFixpoint()` vs
      `_enumerateConstraintsForCellPdcg`
- [ ] Implement lightweight state snapshot for candidate testing
      (clone only cells/options, skip constraint deep-clone)
- [ ] Consider batch constraint generation (pre-compute Map<cell,
      List<Constraint>> after each propagation)
- [x] Add `maxAttemptTime` watchdog — covered by the worker's
      `shouldStop` deadline (honoured at each PDCG iteration) plus the
      `maxStall` no-progress watchdog now wired into the PDCG loop
- [ ] Target: < 30 s per 30×20 puzzle

## Priority 8 — Validate and harden

- [ ] Write unit tests for `_enumerateConstraintsForCellPdcg`:
      - Each slug produces exactly the expected candidates
      - Target cell outside the cell's range → no candidates
- [ ] Write unit tests for seed placement:
      - Centre bias is correct (seed cells are the closest to centre)
      - Seed size clamped to [3, totalCells]
- [ ] Write integration tests:
      - 100 consecutive PDCG generations all pass `solveExplained()`
      - No two consecutive puzzles produce the same line
- [ ] Add PDCG-specific reject reason counters to the CLI dashboard
- [ ] Collect generation statistics:
      - Average constraints per puzzle by size
      - Slug frequency distribution (verify round-robin effect)
      - Acceptance rate (accepted / tested candidates)

## Priority 9 — Ban QA on non-full puzzles

- [ ] In the PDCG strategy, skip QA candidates when the puzzle
      still has too many free cells (only allow QA for the last 3-4
      cells). QA (Quantity) tends to "finalise" deduction brute-force,
      producing traces where the entire endgame is QA-driven instead
      of using more interesting constraints.
- [ ] Define a threshold (e.g. `freeCells <= 4` or
      `freeCells / totalCells <= 0.05`) below which QA is permitted;
      above it, filter QA out of the candidate list.
- [ ] Verify on generated puzzles that the solve trace no longer
      ends with a long QA tail.
