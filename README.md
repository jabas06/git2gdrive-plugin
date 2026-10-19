# git2gdrive

Mirror a **local git repository's tracked files into a Google Drive folder** — one-directional,
idempotent, and safe to re-run. Packaged as an agent plugin for Claude Code, Codex, and Cursor.

The target Drive folder is a parameter, so one install works for every repo you own.

## What it does

The skill mirrors exactly the output of `git ls-files` — tracked files only — recreating the nested
directory structure as Drive subfolders under a folder you choose. The direction is always
**local git → Drive**:

- **Update-in-place** — an existing Drive file is matched by name within its parent folder and its
  content is updated in place, so the Drive file id and any shared links stay stable.
- **Create-if-missing** — a file is created only when absent, so re-running never produces
  duplicates.
- **Never deletes by default** — nothing in Drive is removed or trashed unless you explicitly ask
  for a prune sync with `--prune` (see [Prune sync](#prune-sync)).

## What it does *not* do

- **No pruning unless asked.** Files deleted or renamed locally leave their old Drive copies behind
  until you run a prune sync.
- **No untracked files.** Anything untracked or git-ignored is skipped entirely.
- **Regular files only.** A tracked path that isn't a regular file is skipped and logged rather than
  failing the sync: a symlink to a directory, a dangling symlink, a submodule, or a tracked file
  deleted from the working tree. A symlink to a regular file uploads the content it points to.
- **Uncommitted edits *are* uploaded.** File content is read from the working tree, not from a
  commit, so local modifications to tracked files ship as-is. Commit first if you want the mirror to
  match a commit.
- **No Drive → git direction**, and **no conflict detection** — an edit made in Drive is silently
  overwritten on the next sync.

## Requirements

- `git` and `jq` on `PATH`.
- The [`gws` Google Workspace CLI](https://github.com/googleworkspace/cli), authenticated:

  ```bash
  brew install googleworkspace-cli   # or see the repo for other platforms
  gws auth login                     # gws auth status  -> check
  ```

  `gws` is a community tool, not an officially supported Google product. It uses the billing project
  of the current authenticated session, so no project id is needed here.
- Write access (`canAddChildren` / `canEdit`) to the target Drive folder.

## Install

This repo is itself a single-plugin marketplace, so pointing your client at the repo is enough.

**Claude Code**

```
/plugin marketplace add jabas06/git2gdrive-plugin
/plugin install git2gdrive@git2gdrive
```

or from the CLI:

```bash
claude plugin marketplace add jabas06/git2gdrive-plugin
claude plugin install git2gdrive@git2gdrive
```

**Codex**

```bash
codex plugin marketplace add https://github.com/jabas06/git2gdrive-plugin
codex plugin add git2gdrive@git2gdrive
```

Codex has no `update` command — re-running `plugin add` refreshes the installed copy.

**From a local clone.** Both clients also accept a path, which is the route to use while this repo is
private (or when developing against it):

```bash
git clone https://github.com/jabas06/git2gdrive-plugin.git
claude plugin marketplace add ./git2gdrive-plugin && claude plugin install git2gdrive@git2gdrive
codex  plugin marketplace add ./git2gdrive-plugin && codex  plugin add git2gdrive@git2gdrive
```

**Cursor**

Cursor has no plugin-install CLI. Two ways in:

*From a local clone* — link the repo into Cursor's local plugin root, then restart Cursor (or run
**Developer: Reload Window**):

```bash
ln -s "$PWD/git2gdrive-plugin" ~/.cursor/plugins/local/git2gdrive
```

*From the marketplace* — **Customize** → **+ Add** → **From GitHub Repository**, paste the repo URL,
then install the plugin.

Either way the skill shows up under **Customize**. Cursor reads `.cursor-plugin/plugin.json` from
the plugin root, and `.cursor-plugin/marketplace.json` makes the repo itself a marketplace source.

## Usage

```
/git2gdrive:sync-git-to-gdrive [--folder-id <DRIVE_FOLDER_ID>] [--repo <local-repo-path>] [--prune]   # Claude Code
$git2gdrive:sync-git-to-gdrive [--folder-id <DRIVE_FOLDER_ID>] [--repo <local-repo-path>] [--prune]   # Codex
/sync-git-to-gdrive [--folder-id <DRIVE_FOLDER_ID>] [--repo <local-repo-path>] [--prune]              # Cursor
```

You can also just ask your agent to sync, mirror, or back up a repo's tracked files to Drive — the
skill is selected from its description too. Asking for a "prune sync" or to "prune" is what turns on
`--prune`.

### Parameters

| Parameter | Required | Meaning |
|---|---|---|
| `--folder-id <id>` | only without a pin | The Drive folder that is the mirror root. Optional once the repo's `AGENTS.md` or `README.md` pins one. |
| `--repo <path>` | no | A **local** git work-tree. Defaults to the current directory. |
| `--prune` | no | Prune sync: also trash stale Drive files and empty folders. Previews first; the agent asks before applying with `--yes`. |

The folder id is the last segment of the folder's Drive URL —
`https://drive.google.com/drive/folders/<FOLDER_ID>`. The skill resolves it from the flag first, then
from the repo's pin, and otherwise asks instead of guessing. Remote/`http` repo URLs are rejected;
the repo must be a local work-tree.

### Pinning the target folder

After a successful sync of a repo that has no pin yet, the skill records the Drive folder in the repo
on its own, without asking in the conversation first. It writes the pin as a normal file edit, so
your agent's permission mode decides whether that edit goes through — in a mode that prompts for
edits you approve or reject it like any other change. It appends this section:

```markdown
## Google Drive mirror

Tracked files of this repo are mirrored to:
https://drive.google.com/drive/folders/<FOLDER_ID>

Re-sync with the sync-git-to-gdrive skill; no folder id needs to be passed.
```

The pin goes into the work-tree root's `AGENTS.md` when it exists, otherwise into its `README.md`.
If the repo has neither, nothing is pinned — the skill never creates a file just to hold the pin —
and the next run needs `--folder-id` again. The edit is left uncommitted for you to commit.

The skill never writes a second `Google Drive mirror` section: an existing one, even an incomplete
one, is fixed in place.

With that section committed, later runs need no `--folder-id`: the skill reads the URL from
`AGENTS.md`, then `README.md` (`AGENTS.md` wins if both pin different folders), and derives the id
from its last path segment. An explicit flag still wins; if it points somewhere else, the skill
names both folders and updates the pinned URL in place, again through a regular edit your
permission mode governs. Reject that edit and the pin keeps the previous folder. The bundled script
has no such lookup — running it directly always requires `--folder-id`.

### Prune sync

The default sync only adds and updates. A **prune sync** additionally moves to the Drive trash every
ordinary file under the mirror root that no longer matches a tracked file, and any subfolder left
empty — the mirror folder is treated as dedicated to the repo, so hand-added files count as stale
too. Google Docs/Sheets/Slides, shortcuts and other Drive-native items are never touched, and
nothing is permanently deleted: everything lands in the trash, where it stays recoverable.

It is always two steps. The first run previews, the second applies:

```bash
skills/sync-git-to-gdrive/scripts/sync-git-to-gdrive.sh --folder-id <id> --prune         # sync + "would trash ..." list, nothing removed
skills/sync-git-to-gdrive/scripts/sync-git-to-gdrive.sh --folder-id <id> --prune --yes   # sync + trash the listed items
```

Through the skill, the agent runs the preview, shows you the list and only re-runs with `--yes`
after you confirm. It never turns pruning on for a plain "sync"; you have to ask for a prune sync.
The script refuses to prune when no tracked file can be mirrored (exit 4), since that would empty the
folder. Skipped paths count as stale, so a Drive copy left from an earlier sync of one is trashed.

### Running the script directly

The skill is a thin wrapper around a bundled shell script, which you can also run yourself:

```bash
skills/sync-git-to-gdrive/scripts/sync-git-to-gdrive.sh \
  --folder-id 1AbCdEfGhIjKlMnOpQrStUvWxYz \
  --repo ~/code/my-project
```

## How it works

`git ls-files -z` enumerates the tracked files, and any path that isn't a regular file (after
following symlinks) is skipped. For each remaining one, the script walks the file's parent
directory chain, finding or creating a matching Drive subfolder at each level (memoized, so each
folder is resolved once). It then looks for a non-folder child with the same name: if one exists it
is updated with `gws drive files update --upload`, otherwise a new file is created with
`gws drive files create --upload`. A per-file `create`/`update`/`skip` log and an
`N created, M updated` summary (plus `K skipped` when any) are printed to stderr.

With `--prune`, the script remembers the id of every file it created or updated, then lists the
Drive tree under the root (one paginated listing per folder) and trashes any ordinary file whose id
it did not touch, followed by any folder left empty, deepest first.

## Verifying a sync

Run it twice. The second run should report **0 created** with every file counted as *updated* — that
is the proof that folder and file matching work and that nothing is being duplicated. Spot-check the
Drive folder too: the tree should match the local tracked tree, with same-named files in different
local directories landing in distinct Drive subfolders.

## Contributing

Issues and pull requests are welcome. The skill is deliberately client-neutral — please keep prose in
`SKILL.md` free of client-specific assumptions, and keep the bundled script POSIX-ish bash that runs
under macOS's `/bin/bash` 3.2.

## License

[MIT](LICENSE)
