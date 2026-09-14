#!/usr/bin/env bash

set -u

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/skills/sync-git-to-gdrive/scripts/sync-git-to-gdrive.sh"
skill="$repo_root/skills/sync-git-to-gdrive/SKILL.md"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/git2gdrive-tests.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

passed=0
failed=0

pass() {
  echo "ok - $1"
  passed=$((passed + 1))
}

fail() {
  echo "not ok - $1" >&2
  if [[ -n "${2:-}" ]]; then
    echo "  $2" >&2
  fi
  failed=$((failed + 1))
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected output to contain '$needle'"
  fi
}

make_fake_gws() {
  local fake_bin="$1"
  mkdir -p "$fake_bin"
  cp "$repo_root/tests/support/fake-gws.sh" "$fake_bin/gws"
  chmod +x "$fake_bin/gws"
}

init_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
}

test_tool_neutral_payload() {
  local matches
  matches="$(grep -Ein 'claude|codex|cursor|chatgpt|openai|anthropic|argument-hint|ARGUMENTS:' "$skill" "$script" || true)"
  if [[ -z "$matches" ]]; then
    pass "skill payload is tool-neutral"
  else
    fail "skill payload is tool-neutral" "$matches"
  fi
}

test_skill_documents_agents_md_pin() {
  local skill_text
  skill_text="$(cat "$skill")"
  assert_contains "skill names AGENTS.md as the pin file" "$skill_text" "AGENTS.md"
  assert_contains "skill documents the pin heading" "$skill_text" "## Google Drive mirror"
  assert_contains "skill asks before writing the pin" "$skill_text" "ask before writing"
}

test_missing_option_values() {
  local output status

  output="$("$script" --folder-id 2>&1)"
  status=$?
  assert_eq "missing --folder-id value exits 2" "2" "$status"
  assert_contains "missing --folder-id value is explained" "$output" "error: --folder-id requires a value."

  output="$("$script" --repo 2>&1)"
  status=$?
  assert_eq "missing --repo value exits 2" "2" "$status"
  assert_contains "missing --repo value is explained" "$output" "error: --repo requires a value."
}

test_create_update_and_default_repo() {
  local case_root="$test_root/create-update" repo fake_bin output
  repo="$case_root/repo"
  fake_bin="$case_root/bin"
  init_repo "$repo"
  mkdir -p "$repo/nested dir"
  printf 'tracked\n' > "$repo/nested dir/tracked file.txt"
  printf 'untracked\n' > "$repo/untracked.txt"
  git -C "$repo" add -- "nested dir/tracked file.txt"
  make_fake_gws "$fake_bin"

  output="$(cd "$repo" && PATH="$fake_bin:$PATH" FAKE_GWS_MODE=missing \
    FAKE_GWS_CALLS="$case_root/calls-create" FAKE_GWS_PARAMS="$case_root/params-create" \
    "$script" --folder-id root-folder 2>&1)"
  assert_contains "default repo creates the tracked file" "$output" \
    "1 tracked files processed: 1 created, 0 updated."
  if [[ "$output" != *"untracked.txt"* ]]; then
    pass "default repo skips untracked files"
  else
    fail "default repo skips untracked files"
  fi

  output="$(cd "$repo" && PATH="$fake_bin:$PATH" FAKE_GWS_MODE=existing \
    FAKE_GWS_CALLS="$case_root/calls-update" FAKE_GWS_PARAMS="$case_root/params-update" \
    "$script" --folder-id root-folder 2>&1)"
  assert_contains "a repeated sync updates instead of creating" "$output" \
    "1 tracked files processed: 0 created, 1 updated."
}

test_drive_query_escaping() {
  local case_root="$test_root/query-escaping" repo fake_bin filename output actual expected
  repo="$case_root/repo"
  fake_bin="$case_root/bin"
  init_repo "$repo"
  filename="quinn's\\paper.txt"
  printf 'special\n' > "$repo/$filename"
  git -C "$repo" add -- "$filename"
  make_fake_gws "$fake_bin"

  output="$(PATH="$fake_bin:$PATH" FAKE_GWS_MODE=missing \
    FAKE_GWS_CALLS="$case_root/calls" FAKE_GWS_PARAMS="$case_root/params" \
    "$script" --folder-id root-folder --repo "$repo" 2>&1)"
  assert_contains "special-character file is processed" "$output" \
    "1 tracked files processed: 1 created, 0 updated."

  actual="$(head -n 1 "$case_root/params" | jq -r '.q')"
  expected="name='quinn\\'s\\\\paper.txt' and 'root-folder' in parents and trashed=false and mimeType!='application/vnd.google-apps.folder'"
  assert_eq "Drive query escapes apostrophes and backslashes" "$expected" "$actual"
}

test_tool_neutral_payload
test_skill_documents_agents_md_pin
test_missing_option_values
test_create_update_and_default_repo
test_drive_query_escaping

echo ""
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
