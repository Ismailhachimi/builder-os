#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h}"
BIN_DIR="$HOME/.local/bin"
PROFILE="$HOME/.zprofile"
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
if [[ "$PLATFORM" == "darwin" ]]; then
  DATA_DIR="$HOME/Library/Application Support/BuilderOS"
else
  DATA_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/builder-os"
fi
VENV="$DATA_DIR/venv"

info() { print -r -- "==> $*"; }
die() { print -u2 -r -- "Error: $*"; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

[[ "$PLATFORM" == "darwin" || "$PLATFORM" == "linux" ]] ||
  die "Builder OS supports macOS and Linux; detected: $PLATFORM."
has zsh || die "Zsh is required."

install_linux_packages() {
  local missing=()
  has git || missing+=(git)
  has jq || missing+=(jq)
  has curl || missing+=(curl)
  has column || missing+=(util-linux)
  (( ${#missing} == 0 )) && return 0
  if has apt-get; then
    info "Installing required Linux packages: ${missing[*]}"
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  elif has dnf; then
    info "Installing required Linux packages: ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
  else
    die "Install these commands with your package manager, then rerun: ${missing[*]} column"
  fi
}

install_macos_packages() {
  [[ "$ARCH" == "arm64" ]] || die "The MLX runtime requires an Apple Silicon Mac."
  if ! has git; then
    die "Git is missing. Run 'xcode-select --install', finish the installer, then rerun ./install.sh."
  fi
  if ! has brew && [[ ! -x /opt/homebrew/bin/brew ]]; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  has brew || die "Homebrew installation was not found."
  has python3.11 || { info "Installing Python 3.11..."; brew install python@3.11; }
  has jq || { info "Installing jq..."; brew install jq; }
  if [[ ! -x "$HOME/.opencode/bin/opencode" ]] && ! has opencode; then
    info "Installing OpenCode..."
    brew install anomalyco/tap/opencode
  fi
}

install_linux_opencode() {
  if [[ ! -x "$HOME/.opencode/bin/opencode" ]] && ! has opencode; then
    info "Installing OpenCode..."
    curl -fsSL https://opencode.ai/install | bash
  fi
}

case "$PLATFORM" in
  darwin) install_macos_packages ;;
  linux)
    install_linux_packages
    install_linux_opencode
    has systemctl || die "systemd is required for the Linux model service."
    runtime_bin="${BOS_VLLM_BIN:-$(command -v vllm 2>/dev/null || true)}"
    if [[ ! -x "$runtime_bin" ]]; then
      cat >&2 <<'EOF'
Error: vLLM is not available.

On Linux, install and validate a vLLM environment compatible with the
machine's accelerator, drivers, architecture, and Python environment, then
rerun ./install.sh. BOS intentionally does not replace accelerator drivers,
PyTorch, or vLLM automatically.

You may also point BOS at an existing executable:
  export BOS_VLLM_BIN=/absolute/path/to/vllm
EOF
      exit 1
    fi
    ;;
esac

if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  OPENCODE="$HOME/.opencode/bin/opencode"
else
  OPENCODE="$(command -v opencode)"
fi

mkdir -p "$BIN_DIR" "$HOME/.config/bos" "$DATA_DIR"
ln -sfn "$ROOT/bin/bos" "$BIN_DIR/bos"
if [[ "$PLATFORM" == "linux" && -n "${BOS_VLLM_BIN:-}" ]]; then
  CONFIG="$HOME/.config/bos/config.json"
  [[ -f "$CONFIG" ]] || print -r -- '{"selected_model":"default"}' > "$CONFIG"
  jq --arg bin "$BOS_VLLM_BIN" '.vllm_bin=$bin' "$CONFIG" > "$CONFIG.next"
  mv "$CONFIG.next" "$CONFIG"
fi

if [[ ":$PATH:" != *":$BIN_DIR:"* ]] && ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$PROFILE" 2>/dev/null; then
  print '\n# Builder OS\nexport PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE"
fi

if [[ "$PLATFORM" == "darwin" ]]; then
  if [[ ! -x "$VENV/bin/mlx_lm.server" ]]; then
    info "Creating the local MLX service environment..."
    python3.11 -m venv "$VENV"
    "$VENV/bin/python" -m pip install --upgrade pip
  fi
  info "Synchronizing pinned MLX dependencies..."
  "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check -r "$ROOT/requirements.txt"
fi

info "Preparing OpenCode's local provider..."
(cd "$ROOT" && OPENCODE_CONFIG="$ROOT/opencode.json" "$OPENCODE" debug config >/dev/null)

info "Checking the installation..."
BOS_ROOT="$ROOT" BOS_CONFIG_HOME="$HOME/.config/bos" BOS_DATA_HOME="$DATA_DIR" BOS_MLX_VENV="$VENV" "$ROOT/bin/bos" doctor

cat <<EOF

Builder OS is installed for $PLATFORM/$ARCH.

1. Open a new terminal, or run:
     export PATH="\$HOME/.local/bin:\$PATH"

2. Start the recommended local model:
     bos start

3. Open the current project in the coding agent:
     bos open .

Useful commands:
  bos status
  bos top
  bos init my-app
  bos stop
EOF
