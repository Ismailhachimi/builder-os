#!/bin/zsh

source "${0:A:h}/test-helper.zsh"
export BOS_PLATFORM=linux
export BOS_MODEL_PLATFORM=linux
export XDG_DATA_HOME="$HOME/.local/share"

managed_node="$HOME/.local/share/builder-os/node/current/bin"
mkdir -p "$managed_node"
cat > "$managed_node/node" <<'EOF'
#!/bin/zsh
[[ "$1" == "-v" ]] && echo v22.13.0
exit 0
EOF
cat > "$managed_node/npm" <<EOF
#!/bin/zsh
case "\$*" in
  "install -g pnpm@10.12.1")
    cat > "$managed_node/pnpm" <<'PNPM'
#!/bin/zsh
exit 0
PNPM
    chmod +x "$managed_node/pnpm"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$managed_node/node" "$managed_node/npm"

source "$BOS_ROOT/lib/bos/common.zsh"
source "$BOS_ROOT/lib/bos/projects.zsh"

output_file="$TEST_TMP/web-tools.out"
bos_install_web_tools > "$output_file"
output="$(cat "$output_file")"
assert_contains "$output" "Installing pnpm with npm"
assert_eq "$(command -v node)" "$managed_node/node"
assert_eq "$(command -v npm)" "$managed_node/npm"
assert_eq "$(command -v pnpm)" "$managed_node/pnpm"

finish_tests
