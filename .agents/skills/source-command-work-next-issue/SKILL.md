---
name: "source-command-work-next-issue"
description: "Pick the lowest-numbered unassigned open issue on the AruLifts project board, implement it in an isolated Git Worktree, verify, open PR/merge, and close it. Safe for concurrent multi-agent workflows."
---

# source-command-work-next-issue

Use this skill when the user asks to run `work-next-issue` or work on a project issue.

## 1. Concurrency Protection & Issue Selection

Multiple processes or AI agents may run concurrently against the `gillella/AruLifts` repository. To prevent branch collisions, working directory contamination, or duplicate effort:

1. **Find Next Unassigned Open Issue**:
   ```bash
   gh issue list --state open --no-assignee --json number,title --jq 'sort_by(.number) | .[0]'
   ```
   - If no unassigned open issues remain, verify if any issue currently assigned to `@me` requires completion.
   - If no eligible open issues remain, report: `"Board clear — no unassigned open issues."` and STOP.

2. **Atomic Assignee Locking**:
   Immediately claim the issue before taking any further action:
   ```bash
   gh issue edit <ISSUE_NUMBER> --add-assignee "@me"
   ```
   If `gh issue edit` fails because another process claimed it concurrently, re-query for the next unassigned issue.

3. **Update Board Status to "In Progress"**:
   ```bash
   ITEM_ID=$(gh project item-list 2 --owner gillella --format json | jq -r ".items[] | select(.content.number == <ISSUE_NUMBER>) | .id")
   gh project item-edit --project-id PVT_kwHOAB3sds4BdH7A --id "$ITEM_ID" --field-id PVTSSF_lAHOAB3sds4BdH7AzhXrurU --single-select-option-id 47fc9ee4
   ```
   *(Status IDs: Todo=`f75ad846`, In Progress=`47fc9ee4`, Done=`98236657`)*

---

## 2. Isolated Git Worktree Setup (Eliminates Workspace & Branch Conflicts)

**CRITICAL**: NEVER edit files or switch branches directly in the primary workspace root when multiple processes run concurrently. Switching branches in a shared directory mutates files under other active processes and triggers `.git/index.lock` contention.

Always create a dedicated **Git Worktree** in a separate directory:

1. **Create Worktree & Feature Branch**:
   ```bash
   git fetch origin main
   WORKTREE_DIR="../AruLifts-worktree-issue-<ISSUE_NUMBER>"
   BRANCH_NAME="feature/issue-<ISSUE_NUMBER>-<SHORT_SLUG>"

   git worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR" origin/main
   ```

2. **Switch Working Context**:
   Execute ALL file edits, code searches, script runs (`./Tests/run.sh`), and `xcodebuild` commands inside `$WORKTREE_DIR`.

---

## 3. Implementation & Verification

1. **Read Acceptance Criteria**: View full issue body (`gh issue view <ISSUE_NUMBER>`). Checkboxes define acceptance criteria.
2. **Architecture Rules**:
   - Shared business logic lives in `Shared/`.
   - iPhone views live in `AruLifts/Views/`.
   - Watch views live in `WatchApp/`.
   - State and persistence pass exclusively through `WorkoutStore`.
   - Cross-target state sync via `ConnectivityManager`.
3. **Required Verification** inside `$WORKTREE_DIR`:
   - **Logic Tests**: `./Tests/run.sh` (must pass 100% of assertions).
   - **iOS Build**:
     ```bash
     xcodebuild -project AruLifts.xcodeproj -scheme AruLifts -destination 'generic/platform=iOS Simulator' build
     ```
   - **WatchOS Build**:
     ```bash
     xcodebuild -project AruLifts.xcodeproj -scheme "AruLifts Watch App" -destination 'generic/platform=watchOS Simulator' build
     ```

---

## 4. PR, Merge & Worktree Cleanup

Once implementation and verification are complete:

1. **Commit & Push from Worktree**:
   ```bash
   cd "$WORKTREE_DIR"
   git add .
   git commit -m "Implement Issue #<ISSUE_NUMBER>: <TITLE>"
   git push origin "$BRANCH_NAME"
   ```

2. **Pull Request & Squash Merge**:
   ```bash
   gh pr create --title "[#<ISSUE_NUMBER>] <TITLE>" --body "Closes #<ISSUE_NUMBER>"
   gh pr merge --squash --delete-branch
   ```
   *(If `gh pr create` fails due to transient GitHub API errors, merge `$BRANCH_NAME` into `main` and push `origin main` directly).*

3. **Clean Up Worktree**:
   From the main repo root:
   ```bash
   git worktree remove --force "$WORKTREE_DIR"
   ```

4. **Close Issue & Update Board**:
   - Post verification comment:
     ```bash
     gh issue comment <ISSUE_NUMBER> --body "## Verification Summary\n..."
     ```
   - Close issue: `gh issue close <ISSUE_NUMBER>`
   - Move board item to **Done** (`98236657`):
     ```bash
     gh project item-edit --project-id PVT_kwHOAB3sds4BdH7A --id "$ITEM_ID" --field-id PVTSSF_lAHOAB3sds4BdH7AzhXrurU --single-select-option-id 98236657
     ```

---

## Blocker Handling

If an issue is blocked by external hardware or missing requirements:
1. Post a comment describing the blocker on the issue.
2. Unassign yourself (`gh issue edit <ISSUE_NUMBER> --remove-assignee "@me"`).
3. Move board status back to **Todo** (`f75ad846`).
4. Remove worktree: `git worktree remove --force "$WORKTREE_DIR"`.
5. Re-run selection query for the next unassigned issue.
