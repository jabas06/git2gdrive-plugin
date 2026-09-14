---
name: sync-git-to-gdrive
description: Sync, mirror, or back up a local git repo's tracked files (git ls-files) to a Google Drive folder — one-directional, update-in-place, create-if-missing, never deletes. Requires gws (authenticated), git, jq.
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

Read the flags below from the skill invocation or surrounding request; anything not present takes
its default.

| Parameter | Source | Required | Meaning |
|---|---|---|---|
| folder id | `--folder-id` flag, else the repo's pin | yes | The Drive folder id that is the mirror root. |
| repo path | `--repo` flag | no | Path to a **local** git work-tree. Default: current directory. |

Resolve the folder id in this order:

1. The `--folder-id` flag, when the invocation carries one — an explicit flag always wins.
2. Otherwise, the Drive folder URL pinned in the repo's `AGENTS.md` under a `Google Drive mirror`
   heading. The id is the last path segment of
   `https://drive.google.com/drive/folders/<FOLDER_ID>`; drop any `?query` or `#fragment` first.
   Look for that file at the **work-tree root** of the `--repo` path (`git rev-parse
   --show-toplevel`), not in the current directory. When the id comes from the pin, say so before
   running — "using the Drive folder pinned in AGENTS.md" — so its source is visible.
3. Otherwise, ask for the folder URL or id. There is no default; never guess one.

The repo must be a **local mounted git work-tree**; remote/http repo URLs are rejected. gws uses the
billing project of the current authenticated session, so no project id is needed.

## How to run

Resolve relative paths from this skill's directory and run the bundled script:

```bash
scripts/sync-git-to-gdrive.sh \
  --folder-id <DRIVE_FOLDER_ID> \
  [--repo <local-repo-path>]
```

Supply `--folder-id` with the requested Drive folder id. Omit `--repo` to use the current directory.

Run it **after committing changes** (and, for generated artifacts, after regenerating them) so the
mirror reflects the current tracked tree. The script prints a per-file `create`/`update` log and a
`N created, M updated` summary.

The script itself always needs `--folder-id`: resolve the id first, then pass it through.

## Pin the target folder (after a successful sync)

When the script exits 0 **and** step 2 above found no pin, suggest recording the folder in the repo
so the next run needs no folder id. Show this snippet, with `<FOLDER_ID>` replaced by the id just
used, and **ask before writing anything**:

```markdown
## Google Drive mirror

Tracked files of this repo are mirrored to:
https://drive.google.com/drive/folders/<FOLDER_ID>

Re-sync with the sync-git-to-gdrive skill; no folder id needs to be passed.
```

On approval, append the section to the work-tree root's `AGENTS.md`, or create that file containing
just this section if it does not exist yet.

Two cases where the suggestion changes:

- **A pin already exists and matches** — say nothing; do not re-suggest on every sync.
- **A pin exists but disagrees with an explicit `--folder-id`** — point out the mismatch and offer to
  update the pinned URL to the folder just synced, again asking first. Never rewrite it silently.

## Verification

- Re-run the script: the summary should report **0 created** and every file as **updated** (proves
  idempotency — no duplicates).
- Spot-check the Drive folder: the tree matches the local tracked tree; same-named files in different
  local folders map to distinct Drive subfolders (not duplicates within one folder).
- With the pin in place, re-run **without** `--folder-id`: the id resolves from `AGENTS.md`, the same
  folder is targeted, and the summary again reports 0 created.
