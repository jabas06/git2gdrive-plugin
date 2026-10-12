---
name: sync-git-to-gdrive
description: Sync, mirror, or back up a local git repo's tracked files (git ls-files) to a Google Drive folder — one-directional, update-in-place, create-if-missing. Never deletes by default; a "prune sync" that also trashes stale Drive files is opt-in only, with preview and confirmation. Requires gws (authenticated), git, jq.
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
- **Never deletes by default** — stale Drive copies of files that were removed or renamed locally
  are **left as-is**. Removing them is a separate, explicitly requested step: see
  [Prune sync](#prune-sync) below.

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
| prune | `--prune` flag, or an unambiguous request for a prune sync | no | Also trash stale Drive files. Default: off. See [Prune sync](#prune-sync). |

Resolve the folder id in this order:

1. The `--folder-id` flag, when the invocation carries one — an explicit flag always wins.
2. Otherwise, the Drive folder URL pinned under a `Google Drive mirror` heading in the repo's
   `AGENTS.md` or, failing that, its `README.md`. The id is the last path segment of
   `https://drive.google.com/drive/folders/<FOLDER_ID>`; drop any `?query` or `#fragment` first.
   Look for those files at the **work-tree root** of the `--repo` path (`git rev-parse
   --show-toplevel`), not in the current directory. When the id comes from the pin, say so before
   running — "using the Drive folder pinned in AGENTS.md" (or README.md) — so its source is visible.
3. Otherwise, ask for the folder URL or id. There is no default; never guess one.

The repo must be a **local mounted git work-tree**; remote/http repo URLs are rejected. gws uses the
billing project of the current authenticated session, so no project id is needed.

## How to run

Resolve relative paths from this skill's directory and run the bundled script:

```bash
scripts/sync-git-to-gdrive.sh \
  --folder-id <DRIVE_FOLDER_ID> \
  [--repo <local-repo-path>] \
  [--prune [--yes]]
```

Supply `--folder-id` with the requested Drive folder id. Omit `--repo` to use the current directory.
Omit `--prune` unless a prune sync was explicitly requested.

Run it **after committing changes** (and, for generated artifacts, after regenerating them) so the
mirror reflects the current tracked tree. The script prints a per-file `create`/`update` log and a
`N created, M updated` summary.

The script itself always needs `--folder-id`: resolve the id first, then pass it through.

## Prune sync

A prune sync additionally moves to the Drive **trash** every ordinary file under the mirror root that
no longer corresponds to a tracked file, and any subfolder that is left empty. The mirror folder is
treated as dedicated to this repo, so files someone added there by hand are stale too. Google
Docs/Sheets/Slides, shortcuts and other Drive-native items are never touched, and nothing is ever
permanently deleted — the trash keeps items recoverable.

Pass `--prune` **only** when the invocation carries that exact flag, or the request unambiguously
asks for it — "prune sync", "prune", "delete/remove the stale files", "make Drive match the repo
exactly". Plain "sync", "mirror", "back up", "update" or "refresh" mean the default, non-deleting
sync. When in doubt, do the default sync and mention that a prune sync is available.

Pruning is always two runs:

1. `--prune` alone syncs as usual and then prints `would trash <path>` for each stale item plus a
   summary; nothing is removed. Show that list to the user and ask them to confirm.
2. Only after they confirm, re-run the same command with `--prune --yes`. That run trashes the listed
   items and prints `trash <path>` for each.

Never skip the preview, never add `--yes` on the first run, and stop if the preview looks wrong (for
example the list contains files that clearly belong to another repo — the folder id is probably
wrong). The script refuses to prune when the repo has no tracked files (exit 4).

## Pin the target folder (after a successful sync)

When the script exits 0 **and** step 2 above found no pin, record the folder in the repo yourself so
the next run needs no folder id — do not ask in the conversation first. Make the change as an
ordinary file edit; the agent's own permission mode is what approves or rejects it, so the user
still sees and controls every write. Append this section, with `<FOLDER_ID>` replaced by the id just
used:

```markdown
## Google Drive mirror

Tracked files of this repo are mirrored to:
https://drive.google.com/drive/folders/<FOLDER_ID>

Re-sync with the sync-git-to-gdrive skill; no folder id needs to be passed.
```

Pick the file at the work-tree root, in this order:

1. `AGENTS.md`, when it exists.
2. Otherwise `README.md`, when it exists.
3. Otherwise pin nothing. **Never create either file** just to hold the pin; say that no pin was
   written because the repo has neither file, so the next run needs `--folder-id` again.

After writing, say which file now holds the pin. If the edit is rejected, accept that: do not retry
or fall back to the other file, and mention that the next run needs `--folder-id`. Pinning only
edits the working tree; committing the change is left to the user.

Two cases where the pin step changes:

- **A pin already exists and matches** — say nothing and edit nothing.
- **A pin exists but disagrees with an explicit `--folder-id`** — point out the mismatch and update
  the pinned URL in place, in whichever file holds it, to the folder just synced. The permission
  mode again approves or rejects the edit; never add a second `Google Drive mirror` section.

## Verification

- Re-run the script: the summary should report **0 created** and every file as **updated** (proves
  idempotency — no duplicates).
- Spot-check the Drive folder: the tree matches the local tracked tree; same-named files in different
  local folders map to distinct Drive subfolders (not duplicates within one folder).
- With the pin in place, re-run **without** `--folder-id`: the id resolves from the pin, the same
  folder is targeted, and the summary again reports 0 created.
