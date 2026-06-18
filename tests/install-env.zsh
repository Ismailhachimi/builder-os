#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

source <(sed -n '/^ensure_bin_path()/q; p' "$BOS_ROOT/install.sh")

env_file="$TEST_TMP/.env"

env_set_key "$env_file" HF_TOKEN ""
assert_contains "$(cat "$env_file")" "HF_TOKEN="
env_has_key HF_TOKEN "$env_file" && has_key=yes || has_key=no
env_has_value HF_TOKEN "$env_file" && has_value=yes || has_value=no
assert_eq "$has_key" "yes"
assert_eq "$has_value" "no"

env_set_key "$env_file" HF_TOKEN "hf_test"
assert_contains "$(cat "$env_file")" "HF_TOKEN=hf_test"
env_has_value HF_TOKEN "$env_file" && has_value=yes || has_value=no
assert_eq "$has_value" "yes"

export ROOT="$TEST_TMP/root"
mkdir -p "$ROOT"
print -r -- "HF_TOKEN=" > "$ROOT/.env.example"
setup_local_env
assert_contains "$(cat "$ROOT/.env")" "HF_TOKEN="

finish_tests
