#!/bin/zsh

source "${0:A:h}/test-helper.zsh"
export BOS_PLATFORM=linux
export BOS_MODEL_PLATFORM=linux
export BOS_VLLM_BIN="$TEST_TMP/bin/vllm"
export HF_TOKEN="hf_test_token"
export HF_HUB_DISABLE_XET=1

cat > "$TEST_TMP/bin/systemctl" <<'EOF'
#!/bin/zsh
case "$*" in
  *"is-active"*) [[ -f "$HOME/service-loaded" ]] ;;
  *" start "*) touch "$HOME/service-loaded" "$HOME/healthy" ;;
  *" stop "*) rm -f "$HOME/service-loaded" "$HOME/healthy" ;;
  *) return 0 ;;
esac
EOF
cat > "$TEST_TMP/bin/vllm" <<'EOF'
#!/bin/zsh
exit 0
EOF
cat > "$TEST_TMP/bin/curl" <<'EOF'
#!/bin/zsh
[[ -f "$HOME/healthy" ]]
EOF
cat > "$TEST_TMP/bin/lsof" <<'EOF'
#!/bin/zsh
[[ -f "$HOME/healthy" ]] && echo 4242
EOF
cat > "$TEST_TMP/bin/ps" <<'EOF'
#!/bin/zsh
case "$*" in
  *rss=*) echo 4096000 ;;
  *%cpu=*) echo 8.4 ;;
  *etime=*) echo 01:42 ;;
esac
EOF
chmod +x "$TEST_TMP/bin/"*
mkdir -p "$HOME/.cache/huggingface/hub/models--QuantTrio--Qwen3-Coder-30B-A3B-Instruct-AWQ/snapshots/test"

output="$("$BOS_ROOT/bin/bos" start --model default)"
assert_contains "$output" "Ready"
assert_eq "$(jq -r .platform "$BOS_DATA_HOME/runtime/model.json")" "linux"
assert_eq "$(jq -r .runtime "$BOS_DATA_HOME/runtime/model.json")" "vllm"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "QuantTrio/Qwen3-Coder-30B-A3B-Instruct-AWQ"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "--enforce-eager"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" 'export PATH='
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "export HF_HUB_DISABLE_XET=1"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "export HF_TOKEN=hf_test_token"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "export HUGGING_FACE_HUB_TOKEN=hf_test_token"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/builder-os-model.service")" "ExecStart="

output="$("$BOS_ROOT/bin/bos" status)"
assert_contains "$output" "linux / vllm"

output="$("$BOS_ROOT/bin/bos" model select coder-next)"
assert_contains "$output" "Selected default model: coder-next"

output="$("$BOS_ROOT/bin/bos" stop)"
assert_contains "$output" "stopped"

touch "$HOME/service-loaded"
rm -f "$HOME/healthy"
output="$("$BOS_ROOT/bin/bos" start --model default)"
assert_contains "$output" "Restarting unhealthy model service"
assert_contains "$output" "Ready"

finish_tests
