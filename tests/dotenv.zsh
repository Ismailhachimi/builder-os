#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

mkdir -p "$TEST_TMP/root"
cat > "$TEST_TMP/root/.env" <<'EOF'
# local development secrets
HF_TOKEN=hf_from_env
export BOS_PORT=9090
QUOTED_VALUE="hello world"
SINGLE_QUOTED='soft launch'
PRESET_VALUE=
INVALID-NAME=ignored
EOF

export BOS_ROOT="$TEST_TMP/root"
export PRESET_VALUE="keep-me"
source "$TEST_ROOT/lib/bos/common.zsh"

assert_eq "$HF_TOKEN" "hf_from_env"
assert_eq "$BOS_PORT" "9090"
assert_eq "$QUOTED_VALUE" "hello world"
assert_eq "$SINGLE_QUOTED" "soft launch"
assert_eq "$PRESET_VALUE" "keep-me"
[[ -z "${INVALID:-}" ]] && ignored_invalid=yes || ignored_invalid=no
assert_eq "$ignored_invalid" "yes"

finish_tests
