#!/usr/bin/env bash

set -euo pipefail

: "${FAKE_GWS_MODE:?FAKE_GWS_MODE is required}"
: "${FAKE_GWS_CALLS:?FAKE_GWS_CALLS is required}"
: "${FAKE_GWS_PARAMS:?FAKE_GWS_PARAMS is required}"

printf '%s\n' "$*" >> "$FAKE_GWS_CALLS"

command_name="${1:-} ${2:-} ${3:-}"
case "$command_name" in
  "drive files list")
    shift 3
    params=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --params) params="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "$params" >> "$FAKE_GWS_PARAMS"
    if [[ "$FAKE_GWS_MODE" == "existing" ]]; then
      printf '{"files":[{"id":"existing-id","name":"existing"}]}\n'
    else
      printf '{"files":[]}\n'
    fi
    ;;
  "drive files create")
    printf '{"id":"created-id"}\n'
    ;;
  "drive files update")
    printf '{"id":"updated-id"}\n'
    ;;
  *)
    echo "unexpected fake gws command: $command_name" >&2
    exit 64
    ;;
esac
