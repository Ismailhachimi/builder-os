#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

output="$("$BOS_ROOT/bin/bos" help)"
assert_contains "$output" "start [--model PROFILE]"

output="$("$BOS_ROOT/bin/bos" models)"
assert_contains "$output" "coder-next"
assert_contains "$output" "Qwen3.6"

"$BOS_ROOT/bin/bos" model select coder-next >/dev/null
assert_eq "$(jq -r .selected_model "$BOS_CONFIG_HOME/config.json")" "coder-next"

mkdir -p "$TEST_TMP/repo/.git"
cd "$TEST_TMP/repo"
source "$BOS_ROOT/lib/bos/common.zsh"
source "$BOS_ROOT/lib/bos/projects.zsh"
bos_register_project sample "$TEST_TMP/repo" existing
output="$(bos_projects)"
assert_contains "$output" "sample"
assert_contains "$output" "$TEST_TMP/repo"

custom="$BOS_CONFIG_HOME/templates/custom.json"
mkdir -p "${custom:h}"
print -r -- '{"name":"custom","extends":"web","defaults":{"database":"none"}}' > "$custom"
assert_eq "$(jq -r '.extends' "$custom")" "web"

finish_tests
