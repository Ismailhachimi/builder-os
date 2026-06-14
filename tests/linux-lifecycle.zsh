#!/bin/zsh

source "${0:A:h}/test-helper.zsh"
export BOS_PLATFORM=linux
export BOS_VLLM_BIN="$TEST_TMP/bin/vllm"

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

output="$("$BOS_ROOT/bin/bos" start --model default)"
assert_contains "$output" "Ready"
assert_eq "$(jq -r .platform "$BOS_DATA_HOME/runtime/model.json")" "linux"
assert_eq "$(jq -r .runtime "$BOS_DATA_HOME/runtime/model.json")" "vllm"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "Qwen/Qwen3-Coder-30B-A3B-Instruct"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/builder-os-model.service")" "ExecStart="

output="$("$BOS_ROOT/bin/bos" status)"
assert_contains "$output" "linux / vllm"

output="$("$BOS_ROOT/bin/bos" model select coder-next 2>&1 || true)"
assert_contains "$output" "exceed the practical memory budget"

output="$("$BOS_ROOT/bin/bos" stop)"
assert_contains "$output" "stopped"

finish_tests
