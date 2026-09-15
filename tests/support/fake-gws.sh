#!/usr/bin/env bash
#
# Fake `gws` for the tests. Two modes:
#   - FAKE_GWS_MODE=missing|existing : every `files list` answers "no match" / "one match".
#   - FAKE_GWS_TREE=<json>           : `files list` answers from a fixture tree — a JSON array of
#                                      {id,name,mimeType,parent} items — honouring the parent,
#                                      name and mimeType clauses of the `q` parameter. Items whose
#                                      id was trashed earlier in the run (FAKE_GWS_TRASHED) vanish.
# Every call is appended to FAKE_GWS_CALLS, every list `--params` to FAKE_GWS_PARAMS, and the id
# of every `files update` carrying `"trashed":true` to FAKE_GWS_TRASHED (in call order).

set -euo pipefail

: "${FAKE_GWS_CALLS:?FAKE_GWS_CALLS is required}"
: "${FAKE_GWS_PARAMS:?FAKE_GWS_PARAMS is required}"
FAKE_GWS_MODE="${FAKE_GWS_MODE:-}"
FAKE_GWS_TREE="${FAKE_GWS_TREE:-}"
FAKE_GWS_TRASHED="${FAKE_GWS_TRASHED:-/dev/null}"

printf '%s\n' "$*" >> "$FAKE_GWS_CALLS"

read_opt() {
  # read_opt <flag> "$@" -> value of the flag, or empty
  local flag="$1"; shift
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "$flag" ]]; then printf '%s' "${2:-}"; return 0; fi
    shift
  done
}

list_from_tree() {
  local params="$1" q parent name kind trashed
  q="$(jq -r '.q' <<< "$params")"
  parent="$(sed -n "s/.*'\([^']*\)' in parents.*/\1/p" <<< "$q")"
  name="$(sed -n "s/^name='\(.*\)' and '.*/\1/p" <<< "$q")"
  kind="all"
  [[ "$q" == *"mimeType='application/vnd.google-apps.folder'"* ]] && kind="folder"
  [[ "$q" == *"mimeType!='application/vnd.google-apps.folder'"* ]] && kind="file"
  trashed="$(cat "$FAKE_GWS_TRASHED" 2>/dev/null || true)"
  jq -c --arg parent "$parent" --arg name "$name" --arg kind "$kind" --arg trashed "$trashed" '
    ($trashed | split("\n")) as $gone
    | {files: [ .[]
        | select(.parent == $parent)
        | select(($name == "") or (.name == $name))
        | select(($kind == "all")
                 or ($kind == "folder" and .mimeType == "application/vnd.google-apps.folder")
                 or ($kind == "file"   and .mimeType != "application/vnd.google-apps.folder"))
        | select((.id as $id | $gone | index($id)) == null)
        | {id, name, mimeType} ]}' <<< "$FAKE_GWS_TREE"
}

command_name="${1:-} ${2:-} ${3:-}"
case "$command_name" in
  "drive files list")
    shift 3
    params="$(read_opt --params "$@")"
    printf '%s\n' "$params" >> "$FAKE_GWS_PARAMS"
    if [[ -n "$FAKE_GWS_TREE" ]]; then
      list_from_tree "$params"
    elif [[ "$FAKE_GWS_MODE" == "existing" ]]; then
      printf '{"files":[{"id":"existing-id","name":"existing"}]}\n'
    else
      printf '{"files":[]}\n'
    fi
    ;;
  "drive files create")
    printf '{"id":"created-id"}\n'
    ;;
  "drive files update")
    shift 3
    body="$(read_opt --json "$@")"
    if [[ "$body" == *'"trashed":true'* ]]; then
      read_opt --params "$@" | jq -r '.fileId' >> "$FAKE_GWS_TRASHED"
    fi
    printf '{"id":"updated-id"}\n'
    ;;
  *)
    echo "unexpected fake gws command: $command_name" >&2
    exit 64
    ;;
esac
