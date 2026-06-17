#!/bin/zsh

source "${0:A:h}/test-helper.zsh"
export BOS_PLATFORM=linux
export BOS_MODEL_PLATFORM=linux-spark

cat > "$TEST_TMP/bin/systemctl" <<'EOF'
#!/bin/zsh
case "$*" in
  *"is-active"*) [[ -f "$HOME/service-loaded" ]] ;;
  *" start "*) touch "$HOME/service-loaded" "$HOME/healthy" ;;
  *" stop "*) rm -f "$HOME/service-loaded" "$HOME/healthy" ;;
  *) return 0 ;;
esac
EOF
cat > "$TEST_TMP/bin/ollama" <<'EOF'
#!/bin/zsh
case "$1" in
  list)
    print "NAME ID SIZE MODIFIED"
    [[ -f "$HOME/pulled" ]] && print "qwen3.6:35b abc 24GB now"
    ;;
  pull)
    touch "$HOME/pulled"
    ;;
  --version)
    print "ollama version test"
    ;;
esac
EOF
cat > "$TEST_TMP/bin/curl" <<'EOF'
#!/bin/zsh
[[ -f "$HOME/healthy" ]] || exit 1
case "$*" in
  *"/api/tags"*) print '{"models":[{"name":"qwen3.6:35b"}]}' ;;
  *) print '{"data":[]}' ;;
esac
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

if output="$("$BOS_ROOT/bin/bos" start --model default 2>&1)"; then
  print -u2 "FAIL: start should require an explicit model fetch"
  FAILURES+=1
else
  assert_contains "$output" "Model is not downloaded"
  assert_contains "$output" "bos model fetch default"
fi

manifest_dir="$HOME/.ollama/models/manifests/registry.ollama.ai/library/qwen3.6"
blob_dir="$HOME/.ollama/models/blobs"
mkdir -p "$manifest_dir" "$blob_dir"
cat > "$manifest_dir/35b" <<'JSON'
{
  "config": {"digest": "sha256:config"},
  "layers": [{"digest": "sha256:model"}]
}
JSON
touch "$blob_dir/sha256-config" "$blob_dir/sha256-model"
output="$("$BOS_ROOT/bin/bos" start --model default)"
assert_contains "$output" "Ready"
assert_eq "$(jq -r .platform "$BOS_DATA_HOME/runtime/model.json")" "linux-spark"
assert_eq "$(jq -r .runtime "$BOS_DATA_HOME/runtime/model.json")" "ollama"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "OLLAMA_HOST=127.0.0.1:8080"
assert_contains "$(cat "$BOS_DATA_HOME/runtime/model-service.zsh")" "ollama"

output="$("$BOS_ROOT/bin/bos" status)"
assert_contains "$output" "linux-spark / ollama"

output="$("$BOS_ROOT/bin/bos" models)"
assert_contains "$output" "qwen3.6:35b"
assert_contains "$output" "ollama"

finish_tests
