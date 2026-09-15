#!/usr/bin/env bash
#
# sync-git-to-gdrive.sh — mirror a LOCAL git repository's tracked files to a Google Drive folder.
#
# One-directional: local git  ->  Drive. Additive + update-in-place:
#   - update-in-place : an existing Drive file is matched by name within its parent folder and its
#                       content is updated in place, so the Drive file id and any shared links stay stable;
#   - create-if-missing: a file is created only when absent, so re-running never produces duplicates;
#   - never deletes by default: stale Drive copies of files removed/renamed locally are left as-is
#                        unless --prune is given (see below).
#
# Mirrors exactly the output of `git ls-files` (tracked files only), recreating the nested
# directory structure as Drive subfolders. Runs independently of the agent client.
#
# Prerequisites: git, gws (authenticated Google Workspace CLI), jq.
#
# Usage:
#   sync-git-to-gdrive.sh --folder-id <DRIVE_FOLDER_ID> [--repo <path>] [--prune [--yes]]
#
# Parameters:
#   --folder-id <id>  (required) target Drive folder id (the mirror root).
#   --repo <path>     (optional) path to a LOCAL git work-tree; default: $PWD.
#                     Remote/http repo URLs are NOT supported.
#   --prune           after syncing, list every ordinary file under the mirror root that no
#                     longer corresponds to a tracked file, plus the subfolders that would be
#                     left empty ("would trash ..."). Nothing is removed without --yes.
#   --yes             with --prune: actually move those items to the Drive trash (recoverable).
#                     Google Docs/Sheets/Slides, shortcuts and other Drive-native items are
#                     never touched. Refused when the repo has no tracked files.
#
# gws uses the billing project of the current authenticated session, so no
# project id is needed.

set -euo pipefail

FOLDER_MIME="application/vnd.google-apps.folder"

usage() {
  sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//'
}

# --- parse args ---
folder_id=""
repo_path="$PWD"
prune=0
yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --folder-id)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "error: --folder-id requires a value." >&2
        usage >&2
        exit 2
      fi
      folder_id="$2"
      shift 2
      ;;
    --repo)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "error: --repo requires a value." >&2
        usage >&2
        exit 2
      fi
      repo_path="$2"
      shift 2
      ;;
    --prune)      prune=1; shift ;;
    --yes)        yes=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- validate inputs ---
if [[ -z "$folder_id" ]]; then
  echo "error: missing target Drive folder id (--folder-id)." >&2; usage >&2; exit 2
fi
if [[ "$yes" -eq 1 && "$prune" -eq 0 ]]; then
  echo "error: --yes only makes sense together with --prune." >&2; usage >&2; exit 2
fi
if [[ "$repo_path" == *"://"* ]]; then
  echo "error: --repo must be a LOCAL path, not a URL ('$repo_path'). Remote repos are not supported." >&2; exit 2
fi
if [[ ! -d "$repo_path" ]]; then
  echo "error: repo path does not exist: $repo_path" >&2; exit 2
fi

for bin in git gws jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: required tool not found: $bin" >&2; exit 3; }
done

# Resolve to the git work-tree root (also rejects non-git dirs).
repo_root="$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not a git repository: $repo_path" >&2; exit 2
}
cd "$repo_root"

# relative-dir-path -> Drive folder id (memoization cache).
# `dirname` returns "." for top-level files, which maps to the mirror root.
FOLDER_CACHE=$'\n.\t'"$folder_id"$'\n'
ENSURED_ID=""

# Drive file ids created or updated by this run — everything else under the root is stale.
KEEP_IDS=$'\n'

created=0
updated=0
trashed_files=0
trashed_folders=0
preserved=0

# Escape backslashes and single quotes for use inside a Drive `q` string literal.
q_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }

# drive_find_child <parent_id> <name> <kind>
#   kind = "folder" -> match only folders; "file" -> match only non-folders.
# Echoes the first matching id, or empty string if none.
drive_find_child() {
  local parent="$1" name="$2" kind="$3"
  local name_esc mime_clause q
  name_esc="$(q_escape "$name")"
  if [[ "$kind" == "folder" ]]; then
    mime_clause="and mimeType='${FOLDER_MIME}'"
  else
    mime_clause="and mimeType!='${FOLDER_MIME}'"
  fi
  q="name='${name_esc}' and '${parent}' in parents and trashed=false ${mime_clause}"
  gws drive files list \
    --params "$(jq -nc --arg q "$q" \
      '{q:$q, fields:"files(id,name)", pageSize:1, includeItemsFromAllDrives:true, supportsAllDrives:true}')" \
    --format json 2>/dev/null | jq -r '.files[0].id // empty'
}

# ensure_folder <relative_dir> -> sets ENSURED_ID to the Drive folder id, creating the chain as needed.
ensure_folder() {
  local reldir="$1"
  local rest
  case "$FOLDER_CACHE" in
    *$'\n'"$reldir"$'\t'*)
      rest="${FOLDER_CACHE#*$'\n'"$reldir"$'\t'}"
      ENSURED_ID="${rest%%$'\n'*}"
      return 0 ;;
  esac

  local parent base parent_id id
  parent="$(dirname "$reldir")"
  base="$(basename "$reldir")"
  ensure_folder "$parent"; parent_id="$ENSURED_ID"

  id="$(drive_find_child "$parent_id" "$base" folder)"
  if [[ -z "$id" ]]; then
    id="$(gws drive files create \
      --params "$(jq -nc '{supportsAllDrives:true}')" \
      --json "$(jq -nc --arg name "$base" --arg mime "$FOLDER_MIME" --arg pid "$parent_id" \
        '{name:$name, mimeType:$mime, parents:[$pid]}')" \
      --format json | jq -r '.id')"
    echo "  mkdir  $reldir/" >&2
  fi

  FOLDER_CACHE="${FOLDER_CACHE}${reldir}"$'\t'"$id"$'\n'
  ENSURED_ID="$id"
}

# sync_file <path> — mirror one tracked file into Drive.
sync_file() {
  local path="$1" dir name parent_id existing_id
  dir="$(dirname "$path")"
  name="$(basename "$path")"
  ensure_folder "$dir"; parent_id="$ENSURED_ID"

  existing_id="$(drive_find_child "$parent_id" "$name" file)"
  if [[ -n "$existing_id" ]]; then
    gws drive files update \
      --params "$(jq -nc --arg id "$existing_id" '{fileId:$id, supportsAllDrives:true}')" \
      --upload "$path" >/dev/null
    echo "  update $path" >&2
    updated=$((updated + 1))
    KEEP_IDS="${KEEP_IDS}${existing_id}"$'\n'
  else
    existing_id="$(gws drive files create \
      --params "$(jq -nc '{supportsAllDrives:true}')" \
      --json "$(jq -nc --arg name "$name" --arg pid "$parent_id" '{name:$name, parents:[$pid]}')" \
      --upload "$path" --format json | jq -r '.id')"
    echo "  create $path" >&2
    created=$((created + 1))
    KEEP_IDS="${KEEP_IDS}${existing_id}"$'\n'
  fi
}

# --- prune (opt-in) ---

# is_kept <id> — true when the id was created/updated by this run or is a folder the tree needs.
is_kept() {
  case "$KEEP_IDS" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  case "$FOLDER_CACHE" in *$'\t'"$1"$'\n'*) return 0 ;; esac
  return 1
}

# list_children <folder_id> — one "id<TAB>name<TAB>mimeType" line per live child, all pages.
list_children() {
  gws drive files list \
    --params "$(jq -nc --arg q "'$1' in parents and trashed=false" \
      '{q:$q, fields:"nextPageToken,files(id,name,mimeType)", pageSize:1000,
        includeItemsFromAllDrives:true, supportsAllDrives:true}')" \
    --page-all --page-limit 100 --format json </dev/null \
    | jq -r '.files[]? | [.id, .name, .mimeType] | @tsv'
}

# trash_item <id> <label> — move to Drive trash (recoverable), or only report it without --yes.
trash_item() {
  if [[ "$yes" -eq 1 ]]; then
    gws drive files update \
      --params "$(jq -nc --arg id "$1" '{fileId:$id, supportsAllDrives:true}')" \
      --json '{"trashed":true}' >/dev/null </dev/null
    echo "  trash  $2" >&2
  else
    echo "  would trash $2" >&2
  fi
}

# prune_folder <folder_id> <relative_dir> — recurse, trash stale files, then stale empty folders.
# Sets PRUNE_REMAINING to the number of children left in the folder afterwards.
PRUNE_REMAINING=0
prune_folder() {
  local fid="$1" reldir="$2" children remaining=0 cid cname cmime label
  children="$(list_children "$fid")"
  [[ -z "$children" ]] && { PRUNE_REMAINING=0; return 0; }

  while IFS=$'\t' read -r cid cname cmime; do
    [[ -z "$cid" ]] && continue
    if [[ "$reldir" == "." ]]; then label="$cname"; else label="$reldir/$cname"; fi

    if [[ "$cmime" == "$FOLDER_MIME" ]]; then
      prune_folder "$cid" "$label"
      if is_kept "$cid" || [[ "$PRUNE_REMAINING" -gt 0 ]]; then
        remaining=$((remaining + 1))
      else
        trash_item "$cid" "$label/"
        trashed_folders=$((trashed_folders + 1))
      fi
    elif is_kept "$cid"; then
      remaining=$((remaining + 1))
    elif [[ "$cmime" == application/vnd.google-apps.* ]]; then
      echo "  keep   $label (Drive-native item, never touched)" >&2
      preserved=$((preserved + 1))
      remaining=$((remaining + 1))
    else
      trash_item "$cid" "$label"
      trashed_files=$((trashed_files + 1))
    fi
  done <<< "$children"
  PRUNE_REMAINING=$remaining
}

main() {
  echo "Mirroring git-tracked files of $repo_root -> Drive folder ${folder_id}" >&2
  local count=0
  while IFS= read -r -d '' path; do
    sync_file "$path"
    count=$((count + 1))
  done < <(git ls-files -z)

  if [[ "$prune" -eq 0 ]]; then
    echo "" >&2
    echo "Done. ${count} tracked files processed: ${created} created, ${updated} updated." >&2
    return 0
  fi

  if [[ "$count" -eq 0 ]]; then
    echo "" >&2
    echo "error: refusing to prune — the repo has no tracked files, so everything under the Drive folder would be trashed." >&2
    exit 4
  fi

  echo "" >&2
  echo "Pruning stale items under Drive folder ${folder_id}" >&2
  prune_folder "$folder_id" "."

  echo "" >&2
  if [[ "$yes" -eq 1 ]]; then
    echo "Done. ${count} tracked files processed: ${created} created, ${updated} updated, ${trashed_files} files trashed, ${trashed_folders} folders trashed, ${preserved} Drive-native items kept." >&2
  else
    echo "Done. ${count} tracked files processed: ${created} created, ${updated} updated, ${trashed_files} files would be trashed, ${trashed_folders} folders would be trashed, ${preserved} Drive-native items kept." >&2
    echo "Nothing was removed. Re-run with --prune --yes to move the listed items to the Drive trash." >&2
  fi
}

main
