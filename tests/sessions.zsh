#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

cat > "$TEST_TMP/bin/opencode" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "$HOME/opencode-calls"
if [[ "$*" == *"session list"* ]]; then
  cat <<JSON
[
  {"id":"ses_one","title":"First session","directory":"$HOME/project-one"},
  {"id":"ses_two","title":"Second session","directory":"$HOME/project-two"}
]
JSON
elif [[ "$*" == *"session delete"* ]]; then
  echo "deleted"
else
  echo "opened"
fi
EOF
cat > "$TEST_TMP/bin/curl" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$TEST_TMP/bin/"*
export OPENCODE_BIN="$TEST_TMP/bin/opencode"

mkdir -p "$HOME/project-one/subdir" "$HOME/project-two" "$BOS_DATA_HOME/runtime"
"$BOS_ROOT/bin/bos" project register "$HOME/project-one" --name one >/dev/null
"$BOS_ROOT/bin/bos" project register "$HOME/project-two" --name two >/dev/null
print -r -- '{"profile":"default"}' > "$BOS_DATA_HOME/runtime/model.json"

output="$("$BOS_ROOT/bin/bos" sessions --project one)"
assert_contains "$output" "ses_one"
[[ "$output" != *"ses_two"* ]] && filtered=yes || filtered=no
assert_eq "$filtered" "yes"

output="$("$BOS_ROOT/bin/bos" sessions --all --json)"
assert_contains "$output" "ses_two"

mkdir -p "$HOME/project-empty"
"$BOS_ROOT/bin/bos" project register "$HOME/project-empty" --name empty >/dev/null
output="$("$BOS_ROOT/bin/bos" sessions --projects)"
assert_contains "$output" "one (existing) - 1 session"
assert_contains "$output" "empty (existing) - 0 sessions"
assert_contains "$output" "- First session"

output="$("$BOS_ROOT/bin/bos" session list --project two)"
assert_contains "$output" "ses_two"

output="$(cd "$HOME/project-one/subdir" && "$BOS_ROOT/bin/bos" sessions)"
assert_contains "$output" "ses_one"

output="$("$BOS_ROOT/bin/bos" session delete ses_one --yes)"
assert_contains "$output" "deleted"
assert_contains "$(tail -1 "$HOME/opencode-calls")" "session delete ses_one"

output="$("$BOS_ROOT/bin/bos" session resume ses_one --project one)"
assert_contains "$output" "opened"
assert_contains "$(tail -1 "$HOME/opencode-calls")" "--session ses_one"
assert_eq "$(jq -r '.projects[] | select(.name=="one") | .name' "$BOS_CONFIG_HOME/projects.json")" "one"

output="$("$BOS_ROOT/bin/bos" session resume --project two)"
assert_contains "$output" "opened"
assert_contains "$(tail -1 "$HOME/opencode-calls")" "--continue"

output="$("$BOS_ROOT/bin/bos" session resume --project one --latest)"
assert_contains "$output" "opened"
assert_contains "$(tail -1 "$HOME/opencode-calls")" "--continue"

if "$BOS_ROOT/bin/bos" sessions --project one --select >/dev/null 2>&1; then
  non_tty_select_rejected=no
else
  non_tty_select_rejected=yes
fi
assert_eq "$non_tty_select_rejected" "yes"

output="$("$BOS_ROOT/bin/bos" opencode session list)"
assert_contains "$output" "ses_one"
assert_contains "$(tail -1 "$HOME/opencode-calls")" "--pure session list"

finish_tests
