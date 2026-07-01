---
name: review-range
description: Critical code review of a git commit range plus dev-doc synchronization. Trigger this skill whenever the user asks to review a range of commits (e.g. `review-range old_hash..new_hash`, "review the last 3 commits", "audit this branch"), audit recently merged work, or verify that `docs/dev/` still matches the code. The skill produces a critical review report and proposes documentation edits — never code edits. Use it for every "post-merge review", "pre-PR sanity check", or "what changed between A and B" request, even when the user does not say the word "skill".
---

# Review Range

Critical review of a git commit range, with synchronization of `docs/dev/` to the post-range state of the code.

## Hard rules

- **Never modify code.** Every file outside `docs/` is read-only for this skill, including `.dart`, `.kt`, `.swift`, `.yaml`, `.gradle`, `.json`, build configs, tests, ARB files, and assets. If you spot a bug, write it up in the report — do not fix it.
- **Edit Markdown only under `docs/`** (in practice almost always `docs/dev/`). README, CHANGELOG, CLAUDE.md and other top-level docs are off-limits unless the user explicitly opts in.
- **Do not commit, push, stage, or `git add` anything.** Leave the working tree dirty so the user reviews your doc edits before committing them.
- **Do not run builds, tests, formatters, or generators.** Read-only git is enough; running `flutter test` or `dart run bin/generate.dart` is out of scope (see project memory: user runs those himself).

## Arguments

`$ARGUMENTS` is a git range. Accepted forms:

- `old_commit_hash..new_commit_hash` — standard two-dot range; diff between endpoints.
- `old_commit_hash...new_commit_hash` — three-dot range; symmetric difference.
- A single ref (hash, branch, tag) → treat as `<ref>..HEAD`.
- Empty → ask the user for the range before proceeding. Do not invent one.

Validate the range first: `git rev-parse <range>` (or `git log -1 <endpoint>` for each side). If it fails, ask the user to correct it.

## Workflow

### 1. Collect the changes

Use read-only git commands. Suggested calls:

```bash
git log --oneline <range>               # commit list, scan intent
git log <range> --format=fuller         # author/date/full messages for context
git diff <range> --stat                 # files touched, line counts
git diff <range> -- <path>              # full diff for a specific file
git diff <range> --name-only            # bare file list, useful for scripting
```

Read the full diff for any file with non-trivial changes. Do not skim by file name alone — commit messages can lie.

### 2. Critical review

For each meaningful change in the diff, evaluate:

- **Correctness.** Does the code do what its commit message claims? Look for logic errors, off-by-one bugs, broken invariants, missing null/empty handling at real boundaries. For changes under `lib/getsomepuzzle/constraints/`, re-check the `verify` / `apply` / `isCompleteFor` invariants from `CLAUDE.md` — those have caught real regressions before.
- **Scope discipline.** Are there changes unrelated to the stated intent? Drive-by refactors hiding in a "fix" commit? Dead code or commented-out blocks left behind?
- **Testing.** Are new code paths covered? When tests are touched, do they actually exercise the new behaviour or just inflate coverage? Per project rules, each test must be necessary, clear, and well-commented — call out tests that fail these bars.
- **Performance.** Hot loops, allocations in per-cell / per-frame paths, repeated work that could be memoized once per puzzle.
- **API & invariants.** Public surface changes, broken contracts, signatures that callers in this range did not update.
- **Style & idioms.** `dart format` applied? Naming matches the project? `StatefulWidget` + `setState` (no external state manager)? `vue/no-mutating-props` style violations (child mutating parent state directly)?
- **Security / safety.** Untrusted input, file paths, web JS interop, command-injection-shaped string concatenation.

**Report format.** Group findings by severity:

- **Blocker** — must fix before merge: correctness bugs, broken invariants, data loss, security.
- **Major** — should fix soon: significant scope leak, missing tests on risky paths, perf cliffs.
- **Minor** — worth addressing: style drift, dead code, small redundancies.
- **Nit** — optional polish: naming, comments, formatting touch-ups.

For each finding, cite `file:line` (or `file:line_start-line_end`), quote the smallest informative snippet, and explain *why* it is a problem — not just *what*. Be specific. "Consider refactoring" is not a finding.

Drop entire severity sections that have no findings. If the range is clean, say so explicitly — don't manufacture nits.

### 3. Documentation synchronization

Walk every file in `docs/dev/`. Pay special attention to files with explicit checklists:

- `docs/dev/todo.md` — solver / generator / UI improvement ideas, structured as headings + bullets.
- `docs/dev/ready_to_publish.md` — store-submission checklist with `[ ]` / `[x]` items and an `## Already done` trailing section.

For each markdown file, check whether the code changes in the range:

1. **Implement an item from a todo / checklist.**
   - In `todo.md`: remove the bullet (or whole subsection if the entire section is now done). Don't move it elsewhere — `todo.md` is for *open* work only.
   - In `ready_to_publish.md`: move the line from its open section to `## Already done`, flipping `[ ]` → `[x]`. Preserve the prose style of nearby `[x]` entries — they tend to describe *what was done and where*, not just the task name.
   - In any other doc that uses checkboxes: flip `[ ]` → `[x]` in place. Don't reorder unless the file's pattern asks for it.

2. **Invalidate a documented design, invariant, or algorithm.**
   - Rewrite the affected section in place to match the new reality.
   - Do not append a "Note: this changed in commit X" line — devdocs describe the current system, not its history. Git already has the history.

3. **Reference functions / files / flags / classes that the range removed or renamed.**
   - Update the references, or delete the paragraph if it became meaningless.
   - **Grep before editing**: `grep -rn "OldName" lib/ bin/ test/` — if it's truly gone, fix the doc; if it survives elsewhere, the doc may still be correct.

4. **Add a new constraint, generator stage, or solver feature without a doc.**
   - Create `docs/dev/<feature>.md` using the existing style. Look at `EyesConstraint.md`, `neighbor_count.md`, `column_count.md`, or `group_count.md` as size-appropriate templates.
   - Do not create a doc for trivial additions (one-line utility, internal helper) — judgement call; when unsure, recommend in the report rather than write the doc.

**Verify before editing.** A memory of "function X exists in the new tree" is not enough — confirm with `grep` / `git grep` / `git show <new_hash>:<path>` on the post-range state. If you cannot confirm, write a recommendation in the report instead of guessing.

**Do not** rewrite docs cosmetically (typo passes, reflow, prose polish) unless the range itself touches that content. Scope discipline applies to this skill too.

### 4. Final report

End with this template (omit sections that are empty):

```
## Critical review

### Blocker
- `file.dart:42-48` — short title
  > quoted snippet
  why it is wrong, and what the right shape would look like

### Major
- ...

### Minor / Nit
- ...

## Docs synchronization

Edited:
- `docs/dev/todo.md` — removed "GS=1 color-independent deductions" (implemented in commit abc1234)
- `docs/dev/ready_to_publish.md` — moved "Production keystore" to Already done

Not edited (recommended follow-up):
- `docs/dev/equilibrium.md` — references `oldPickTarget()`, renamed to `pickTargetV2()` in this range; needs a rewrite of the "Worker integration" section.

## Suggested follow-up actions

- Add a regression test for the constraint invariant flagged above (`test/constraints_test.dart`).
- Run `dart format` over `lib/getsomepuzzle/constraints/eyes_constraint.dart` before commit.
- Consider a follow-up commit to delete the now-unreachable branch at `puzzle.dart:312`.
```

Keep it short enough that the user reads it in one sitting. The point is to give them a decision-ready punch list, not an essay.

## Things this skill explicitly does NOT do

- Run tests, `flutter analyze`, `flutter build`, `dart format`, `dart run bin/...`, or any other command that touches the working tree, network, or generator state.
- Open PRs, push branches, or post GitHub comments.
- Edit code files even if a finding looks trivial. The user committed the code; the user fixes it. Doc edits are the only writes you make.
- Speculate about commits outside the supplied range. If a finding requires context from earlier history, say so in the report and let the user widen the range.
- Decide a finding is "good enough" and silently skip it. Every blocker / major goes in the report even if you also patched the related doc.
