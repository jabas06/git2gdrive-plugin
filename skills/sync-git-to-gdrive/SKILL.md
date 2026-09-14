---
name: sync-git-to-gdrive
description: Sync, mirror, or back up a local git repo's tracked files (git ls-files) to a Google Drive folder — one-directional, update-in-place, create-if-missing, never deletes. Requires gws (authenticated), git, jq.
argument-hint: "--folder-id <DRIVE_FOLDER_ID> [--repo <local-repo-path>]"
---

# sync-git-to-gdrive

Mirror a **local** git repository's tracked files to a Google Drive folder. Project-agnostic: the
target folder is passed in as a parameter — nothing is hardcoded.

## What it does (behavior contract)

Mirrors exactly `git ls-files` (tracked files only — nothing untracked or git-ignored), recreating the
nested directory structure as Drive subfolders. One-directional, **local git → Drive**:

- **Update-in-place** — an existing Drive file is matched by name within its parent folder and its
  content is updated *in place*, so the Drive file id and any shared links stay stable.
- **Create-if-missing** — a file is created only when absent, so re-running never produces duplicates.
- **Never deletes** — stale Drive copies of files that were removed or renamed locally are **left
  as-is** (no pruning yet; clean them up manually for now — a `--prune` opt-in may be added later).

## Prerequisites

- `git`, the `gws` Google Workspace CLI (authenticated), and `jq` on `PATH`.
- Write access (`canAddChildren` / `canEdit`) to the target Drive folder.

## Input

The text the user gave with this skill — after the slash command or `$`-mention, on an `ARGUMENTS:`
line, or in the surrounding request — holds the arguments below; anything not present takes its
default.

| Parameter | Source | Required | Meaning |
|---|---|---|---|
| folder id | `--folder-id` flag | yes | The Drive folder id that is the mirror root. |
| repo path | `--repo` flag | no | Path to a **local** git work-tree. Default: current directory. |

The folder id is **required** — there is no default; if the input does not carry one, ask for it
rather than guessing. The repo must be a **local mounted git work-tree**; remote/http repo URLs are
rejected. gws uses the billing project of the current authenticated session, so no project id is
needed.

> **Finding the folder id:** it is the last path segment of the folder's Drive URL —
> `https://drive.google.com/drive/folders/<FOLDER_ID>`.

## How to run

Run the bundled script from this skill's `scripts/` directory:

```bash
"${CLAUDE_SKILL_DIR}/scripts/sync-git-to-gdrive.sh" \
  --folder-id <DRIVE_FOLDER_ID> \
  [--repo <local-repo-path>]
```

Run it in exactly that form. Claude Code substitutes `${CLAUDE_SKILL_DIR}`. If your client does not
substitute it (Codex), resolve this skill's directory from the skills catalog: take this skill's
`file:` path, expand its `rN/` prefix with the skill-roots table, and use that SKILL.md's directory.

Run it **after committing changes** (and, for generated artifacts, after regenerating them) so the
mirror reflects the current tracked tree. The script prints a per-file `create`/`update` log and a
`N created, M updated` summary.

## Verification

- Re-run the script: the summary should report **0 created** and every file as **updated** (proves
  idempotency — no duplicates).
- Spot-check the Drive folder: the tree matches the local tracked tree; same-named files in different
  local folders map to distinct Drive subfolders (not duplicates within one folder).
