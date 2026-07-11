---
description: Pick the lowest-numbered open issue on the AruLifts project board, implement it to completion, verify, and close it. One issue per invocation.
---

Work exactly ONE issue per invocation, in progressive order. Repo: gillella/AruLifts. Project board: https://github.com/users/gillella/projects/2 (project number 2, owner gillella).

## 1. Pick the issue

- `gh issue list --state open --json number,title --jq 'sort_by(.number) | .[0]'` — the lowest-numbered open issue is next. Issues #1–#16 are ordered by dependency (e.g. #2 HKWorkoutSession depends on #1 HealthKit setup), so never skip ahead unless the current issue is hard-blocked.
- If no open issues remain: report "board clear" and STOP the loop (ScheduleWakeup stop:true if running under /loop).
- Read the full issue body (`gh issue view N`) — acceptance criteria live there as checkboxes.
- Move its board Status to "In Progress":
  `gh project item-list 2 --owner gillella --format json` to find the item id, then
  `gh project item-edit --project-id PVT_kwHOAB3sds4BdH7A --id <ITEM_ID> --field-id PVTSSF_lAHOAB3sds4BdH7AzhXrurU --single-select-option-id 47fc9ee4`
  (Status option ids: Todo=f75ad846, In Progress=47fc9ee4, Done=98236657).

## 2. Design, then implement

- For issues touching HealthKit, HKWorkoutSession, WatchConnectivity, or new subsystems: get a design first — spawn the `swift-architect` agent if available, otherwise write a brief design yourself (approach, files, risks) before coding.
- Implement via the matching agent when available (`watch-health-dev` for issues #1–#3/#9 Health parts, `ios-feature-dev` for iPhone UI features), otherwise implement directly.
- Respect the architecture: shared logic in `Shared/`, thin platform views, persistence only through `WorkoutStore`, phone↔watch sync via `ConnectivityManager`.
- Work on `main` unless the change is risky; commit in small logical units.

## 3. Definition of done (all required before closing)

1. **Acceptance criteria**: every checkbox in the issue body is either implemented or explicitly commented on the issue as deferred-with-reason. No silent skips.
2. **Builds clean**: both targets compile —
   `xcodebuild -project AruLifts.xcodeproj -scheme AruLifts -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30`
   and the same for scheme `"AruLifts Watch App"` with `generic/platform=watchOS Simulator`. A failed build is an absolute blocker.
3. **Tests pass** if a test target exists; add tests for pure logic (progression math, calculators, deload rules — issues #4–#7 especially).
4. **Runtime verification**: launch in the simulator and exercise the changed flow (boot with `xcrun simctl`, or the `build-runner` agent). Capability/plist issues (HealthKit!) only surface at runtime, never at compile time.
5. **Code review**: spawn the `code-reviewer` agent on the diff (fall back to a self-review pass against correctness, cross-target state sync, and session/timer lifecycle). Fix anything rated ship-blocking.
6. **Committed and pushed** to origin/main. Commit message references the issue (`Fixes #N` style is fine but see step 4 below — prefer manual close with comment).
7. **Verification comment** posted on the issue before closing: what was implemented, how it was verified, and — critically for Watch/HealthKit issues — an explicit **"Needs on-device verification"** checklist for anything the simulator cannot prove (haptics during wrist-down, activity-ring credit, background suspension behavior, real heart-rate samples). Simulator-verified ≠ device-verified; never claim the latter.

## 4. Close out

- Comment per item 7, then `gh issue close N`.
- Move the board item Status to "Done" (option id 98236657).
- Report a short summary: issue closed, files changed, what still needs on-device testing.

## Blockers

If genuinely blocked (needs an Apple developer account action, a product decision, or on-device testing before further progress is safe):
- Comment the blocker on the issue, add a `blocked` label (`gh label create blocked` first if missing), move its Status back to "Todo".
- Move to the NEXT lowest-numbered non-blocked issue. If everything remaining is blocked, stop the loop and summarize the blockers for Aravind.

Never: force-push, delete branches, rewrite history, close an issue whose acceptance criteria aren't met, or mark device-only behavior as verified.
