# omp model roles & usage-cap fallback

Model roles live in `~/.omp/agent/config.yml` (user-level, applies to all projects).

- default: `opencode-go/deepseek-v4-flash:high`; task: `opencode-go/deepseek-v4-flash`
- slow, plan: `opencode-go/deepseek-v4-pro:high`
- vision: `opencode-go/gpt-5.6-luna` (only role with image input besides designer)
- designer: `opencode-zen/gemini-3.7-flash`
- smol: `opencode-zen/nemotron-3-ultra-free` ($0)
- commit, tiny, advisor: `opencode-go/hy3` (near-free)

OpenCode Go is quota-limited on rolling 5h/7d/30d windows; check with `omp usage`.

User preference: when approaching the Go usage cap, REMIND the user and suggest the
fallback of swapping `default`/`task` to `opencode-zen/deepseek-v4-flash-free`
(200K ctx, $0) until the window resets. Never swap silently on your own.