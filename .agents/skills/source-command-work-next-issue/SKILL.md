---
name: "source-command-work-next-issue"
description: "Pick the lowest-numbered available, unblocked, unassigned open issue on the AruLifts project board, implement it in an isolated feature branch, verify, create a PR, and close it. One issue per invocation."
---

# source-command-work-next-issue

Use this skill when the user asks to run the migrated source command `work-next-issue`.

## Command Template

Work exactly ONE issue per invocation, in progressive order. Repo: gillella/AruLifts. Project board: https://github.com/users/gillella/projects/2 (project number 2, owner gillella).

## 1. Concurrency-Safe Issue Selection & Acquisition

1. **Query Available Issues**:
   Select the lowest-numbered open issue that is **unassigned** and **not labeled `blocked`**:
   ```bash
   gh issue list --state open --json number,title,labels,assignees --jq '[.[] | select((.labels | map(.name) | contains(["blocked"]) | not) and (.assignees | length == 0))] | sort_by(.number) | .[0]'
   ```
   - If no eligible open issues remain: report "board clear" and STOP the loop (`ScheduleWakeup stop:true` if running under `/loop`).

2. **Atomic Acquisition (Locking)**:
   - Assign the issue to yourself immediately to prevent concurrent processes from picking the same issue:
     ```bash
     gh issue edit <NUMBER> --add-assignee "@me"
     ```
   - Move board Status to **"In Progress"**:
     `gh project item-list 2 --owner gillella --format json` to find the `<ITEM_ID>`, then:
     ```bash
     gh project item-edit --project-id PVT_kwHOAB3sds4BdH7A --id <ITEM_ID> --field-id PVTSSF_lAHOAB3sds4BdH7AzhXrurU --single-select-option-id 47fc9ee4
     ```
     *(Status option IDs: Todo=f75ad846, In Progress=47fc9ee4, Done=98236657)*.

3. **Read Acceptance Criteria**:
   Read the full issue body (`gh issue view <NUMBER>`) — acceptance criteria live there as checkboxes.

## 2. Feature Branch Setup

1. **Sync with Main**:
   Ensure local `main` is clean and up to date:
   ```bash
   git checkout main && git pull origin main
   ```
2. **Create Feature Branch**:
   Create a dedicated branch for isolation:
   ```bash
   git checkout -b feature/issue-<NUMBER>-<short-slug>
   ```

## 3. Design & Implement

1. **Design First (when applicable)**:
   For issues touching HealthKit, HKWorkoutSession, WatchConnectivity, or new subsystems: write a brief design (approach, files, risks) before coding. Spawn `swift-architect` agent if available.
2. **Implement**:
   Implement via matching agent (`watch-health-dev` for Health/Watch parts, `ios-feature-dev` for iPhone UI features) or directly.
3. **Architecture Rules**:
   Respect architecture: shared logic in `Shared/`, thin platform views, persistence only through `WorkoutStore`, phone↔watch sync via `ConnectivityManager`.

## 4. Verification & Definition of Done

All required before opening PR / closing:

1. **Acceptance Criteria**: Every checkbox in the issue body is either implemented or explicitly commented on the issue as deferred-with-reason.
2. **Clean Builds**: Both targets compile —
   ```bash
   xcodebuild -project AruLifts.xcodeproj -scheme AruLifts -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
   ```
   and the same for scheme `"AruLifts Watch App"` with `generic/platform=watchOS Simulator`. A failed build is an absolute blocker.
3. **Logic Tests Pass**: Run `./Tests/run.sh` to ensure all unit & logic test assertions pass. Add new assertions for new features/logic.
4. **Runtime Verification**: Launch in simulator (`xcrun simctl` or `build-runner`) and exercise changed flows.
5. **Code Review**: Run code review pass against correctness, cross-target sync, and lifecycle.

## 5. Pull Request & Close Out

1. **Push Branch & Open PR**:
   ```bash
   git push origin feature/issue-<NUMBER>-<short-slug>
   gh pr create --title "[#<NUMBER>] <Title>" --body "Closes #<NUMBER>

   ## Summary of Changes
   - <List key changes>

   ## Verification
   - Both iOS and watchOS targets build cleanly
   - Logic tests pass (./Tests/run.sh)
   - Runtime verified in simulator"
   ```
2. **Merge PR**:
   Merge the PR and delete the feature branch:
   ```bash
   gh pr merge --squash --delete-branch
   ```
3. **Close Out & Board Sync**:
   - Post verification comment on the issue (`gh issue comment <NUMBER> --body "..."`).
   - Ensure issue is closed (`gh issue close <NUMBER>`).
   - Move board item Status to **"Done"** (`--single-select-option-id 98236657`).

## 6. Handling Blockers

If genuinely blocked (needs Apple developer account action, product decision, or on-device testing):
1. Add `blocked` label (`gh issue edit <NUMBER> --add-label blocked`).
2. Post a comment on the issue explaining the blocker.
3. Unassign yourself (`gh issue edit <NUMBER> --remove-assignee "@me"`).
4. Move Status back to "Todo".
5. Move to the next lowest-numbered unblocked, unassigned issue.

Never: force-push, delete remote branches prematurely, rewrite history, close an issue whose acceptance criteria aren't met, or work directly on `main` without feature branch isolation.
