#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

mkdir -p "$BOS_ROOT/benchmark/results/99999999-000000-test" "$BOS_ROOT/benchmark/results/99999999-000000-test-runtime"
cat > "$BOS_ROOT/benchmark/results/99999999-000000-test/summary.tsv" <<'EOF'
scenario	seconds	tests
one	10	pass
two	20	fail
EOF
cat > "$BOS_ROOT/benchmark/results/99999999-000000-test-runtime/generation.log" <<'EOF'
Prompt: 10 tokens, 100.000 tokens-per-sec
Generation: 10 tokens, 80.000 tokens-per-sec
Peak memory: 12.500 GB
EOF

source "$BOS_ROOT/lib/bos/common.zsh"
source "$BOS_ROOT/lib/bos/eval.zsh"
output="$(bos_eval_summary test)"
assert_contains "$output" "1/2"
assert_contains "$output" "30"
assert_contains "$output" "100.000"
assert_contains "$output" "12.500GB"

rm -rf "$BOS_ROOT/benchmark/results/99999999-000000-test" "$BOS_ROOT/benchmark/results/99999999-000000-test-runtime"
finish_tests
