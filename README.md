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
- **Never deletes** — nothing in Drive is removed or trashed.

## What it does *not* do

- **No pruning.** Files deleted or renamed locally leave their old Drive copies behind; clean those
  up by hand.
- **No untracked files.** Anything untracked or git-ignored is skipped entirely.
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
/git2gdrive:sync-git-to-gdrive --folder-id <DRIVE_FOLDER_ID> [--repo <local-repo-path>]   # Claude Code
$git2gdrive:sync-git-to-gdrive --folder-id <DRIVE_FOLDER_ID> [--repo <local-repo-path>]   # Codex
/sync-git-to-gdrive --folder-id <DRIVE_FOLDER_ID> [--repo <local-repo-path>]              # Cursor
```

You can also just ask your agent to sync, mirror, or back up a repo's tracked files to Drive — the
skill is selected from its description too.

### Parameters

| Parameter | Required | Meaning |
|---|---|---|
| `--folder-id <id>` | yes | The Drive folder that is the mirror root. |
| `--repo <path>` | no | A **local** git work-tree. Defaults to the current directory. |

The folder id is the last segment of the folder's Drive URL —
`https://drive.google.com/drive/folders/<FOLDER_ID>`. There is no default: when it is missing, the
skill asks instead of guessing. Remote/`http` repo URLs are rejected; the repo must be a local
work-tree.

### Running the script directly

The skill is a thin wrapper around a bundled shell script, which you can also run yourself:

```bash
skills/sync-git-to-gdrive/scripts/sync-git-to-gdrive.sh \
  --folder-id 1AbCdEfGhIjKlMnOpQrStUvWxYz \
  --repo ~/code/my-project
```

## How it works

`git ls-files -z` enumerates the tracked files. For each one, the script walks the file's parent
directory chain, finding or creating a matching Drive subfolder at each level (memoized, so each
folder is resolved once). It then looks for a non-folder child with the same name: if one exists it
is updated with `gws drive files update --upload`, otherwise a new file is created with
`gws drive files create --upload`. A per-file `create`/`update` log and an
`N created, M updated` summary are printed to stderr.

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
