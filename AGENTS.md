# Repository workflow

- Every session that changes code or project files must use its own dedicated
  Git worktree and feature branch. Do not edit the primary checkout directly.
- Before editing, inspect `git status` and `git worktree list`, then create a
  sibling worktree with a uniquely named `codex/` branch from the intended
  base branch.
- Never share one feature branch between worktrees. Preserve unrelated changes
  in every checkout and do not move, overwrite, or clean another session's work.
- Run the relevant tests and builds, commit, push, and create or update the pull
  request from that feature's worktree.
- Read-only investigation may use the primary checkout, but create the worktree
  before making the first file change.

# Acceptance criteria

- `ACCEPTANCE-CRITERIA.md` is the authoritative pass/fail contract for app
  behaviour. A PR that changes user-visible behaviour **updates that document in
  the same PR** — see its §17 for the checklist.
- Criterion IDs are stable and are cited in past run reports. Add new IDs after
  the highest in the area; never renumber existing ones.
- `E2E-TEST-PLAN.md` holds the narrative test goals and the historical results
  log. `ROADMAP.md` holds forward epics. Keep all three consistent with each
  other when behaviour moves.
