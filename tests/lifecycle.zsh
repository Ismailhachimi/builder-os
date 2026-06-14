#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

cat > "$TEST_TMP/bin/launchctl" <<'EOF'
#!/bin/zsh
case "$1" in
  bootstrap) touch "$HOME/service-loaded" "$HOME/healthy" ;;
  bootout) rm -f "$HOME/service-loaded" "$HOME/healthy" ;;
  print) [[ -f "$HOME/service-loaded" ]] ;;
esac
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
  *rss=*) echo 2048000 ;;
  *%cpu=*) echo 4.2 ;;
  *etime=*) echo 00:42 ;;
esac
EOF
chmod +x "$TEST_TMP/bin/"*
mkdir -p "$BOS_MLX_VENV/bin"
touch "$BOS_MLX_VENV/bin/mlx_lm.server"
chmod +x "$BOS_MLX_VENV/bin/mlx_lm.server"

output="$("$BOS_ROOT/bin/bos" start --model default)"
assert_contains "$output" "Ready"
assert_eq "$(jq -r .profile "$BOS_DATA_HOME/runtime/model.json")" "default"

output="$("$BOS_ROOT/bin/bos" status)"
assert_contains "$output" "healthy"
assert_contains "$output" "default"

output="$("$BOS_ROOT/bin/bos" top --once)"
assert_contains "$output" "MODEL SERVICE"
assert_contains "$output" "LATEST EVALUATION"

output="$("$BOS_ROOT/bin/bos" stop)"
assert_contains "$output" "stopped"

finish_tests
