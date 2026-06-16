#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h}"
BIN_DIR="$HOME/.local/bin"
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

ensure_bin_path() {
  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  local profiles=() profile

  case "$PLATFORM" in
    darwin) profiles=("$HOME/.zprofile") ;;
    linux)
      profiles=("$HOME/.profile")
      [[ "${SHELL:-}" == */bash ]] && profiles+=("$HOME/.bashrc")
      [[ "${SHELL:-}" == */zsh ]] && profiles+=("$HOME/.zshrc" "$HOME/.zprofile")
      ;;
  esac

  for profile in "${profiles[@]}"; do
    [[ -n "$profile" ]] || continue
    if ! grep -Fq "$path_line" "$profile" 2>/dev/null; then
      print '\n# Builder OS\n'"$path_line" >> "$profile"
    fi
  done
}

install_bos_command() {
  local user_link="$BIN_DIR/bos"
  local system_link="/usr/local/bin/bos"

  mkdir -p "$BIN_DIR"
  ln -sfn "$ROOT/bin/bos" "$user_link"
  ensure_bin_path

  if command -v bos >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$PLATFORM" == "linux" && ":$PATH:" == *":/usr/local/bin:"* ]]; then
    if [[ -e "$system_link" && ! -L "$system_link" ]]; then
      info "$system_link exists and is not managed by BOS; leaving it unchanged."
    else
      info "Linking bos into /usr/local/bin so it works in this terminal..."
      sudo ln -sfn "$ROOT/bin/bos" "$system_link"
    fi
  fi
}

install_linux_packages() {
  local missing=()
  has git || missing+=(git)
  has jq || missing+=(jq)
  has curl || missing+=(curl)
  if has apt-get; then
    has python3 || missing+=(python3)
    python3 -m venv --help >/dev/null 2>&1 || missing+=(python3-venv)
  else
    has python3 || missing+=(python3)
  fi
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

install_linux_vllm() {
  local vllm_venv="$HOME/venvs/vllm"
  local runtime_bin="$vllm_venv/bin/vllm"
  [[ -x "$runtime_bin" ]] && return 0

  has python3 || die "Python 3 is required to create the Linux vLLM environment."

  info "Creating dedicated vLLM environment: $vllm_venv"
  mkdir -p "$HOME/venvs"
  if [[ ! -x "$vllm_venv/bin/python" ]]; then
    python3 -m venv "$vllm_venv" ||
      die "Could not create $vllm_venv. On Debian/Ubuntu, install python3-venv and rerun ./install.sh."
  fi

  info "Preparing vLLM Python packaging tools..."
  "$vllm_venv/bin/python" -m pip install --upgrade pip setuptools wheel ||
    die "Could not prepare pip inside $vllm_venv."

  info "Installing vLLM into $vllm_venv..."
  "$vllm_venv/bin/python" -m pip install --upgrade vllm ||
    die "vLLM installation failed. Check the pip output above, or set BOS_VLLM_BIN to a compatible local vLLM executable."

  [[ -x "$runtime_bin" ]] ||
    die "vLLM installation completed, but $runtime_bin was not created."
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

validate_linux_vllm() {
  local default_runtime_bin="$HOME/venvs/vllm/bin/vllm"
  local runtime_bin="" runtime_source=""
  if [[ -n "${BOS_VLLM_BIN:-}" ]]; then
    if [[ "$BOS_VLLM_BIN" == */* ]]; then
      runtime_bin="${BOS_VLLM_BIN:A}"
    else
      runtime_bin="$(command -v "$BOS_VLLM_BIN" 2>/dev/null || true)"
    fi
    runtime_source="BOS_VLLM_BIN"
    [[ -n "$runtime_bin" && -x "$runtime_bin" ]] ||
      die "BOS_VLLM_BIN is set, but it does not resolve to an executable vLLM binary: $BOS_VLLM_BIN"
  elif [[ -x "$default_runtime_bin" ]]; then
    runtime_bin="$default_runtime_bin"
    runtime_source="default vLLM environment"
  elif runtime_bin="$(command -v vllm 2>/dev/null)" && [[ -n "$runtime_bin" ]]; then
    runtime_source="PATH"
  else
    install_linux_vllm
    runtime_bin="$default_runtime_bin"
    runtime_source="default vLLM environment"
  fi

  if [[ -z "$runtime_bin" || ! -x "$runtime_bin" ]]; then
    runtime_bin="$(command -v vllm 2>/dev/null || true)"
    [[ -n "$runtime_bin" && -x "$runtime_bin" ]] ||
      die "vLLM is not available. Automatic install failed and no executable vLLM was found."
  fi

  [[ "$runtime_bin" == /* ]] ||
    die "vLLM path must resolve to an absolute executable path; got '$runtime_bin'."

  info "Validating vLLM executable: $runtime_bin"
  [[ "$runtime_source" == "PATH" ]] &&
    info "Tip: a dedicated vLLM environment at $default_runtime_bin is recommended for Linux."

  "$runtime_bin" --version >/dev/null 2>&1 ||
    die "vLLM was found at '$runtime_bin', but 'vllm --version' failed."

  "$runtime_bin" serve --help >/dev/null 2>&1 ||
    die "vLLM was found at '$runtime_bin', but 'vllm serve --help' failed."

  export BOS_VLLM_BIN="$runtime_bin"
}

case "$PLATFORM" in
  darwin) install_macos_packages ;;
  linux)
    install_linux_packages
    install_linux_opencode
    has systemctl || die "systemd is required for the Linux model service."
    validate_linux_vllm
    ;;
esac

if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  OPENCODE="$HOME/.opencode/bin/opencode"
else
  OPENCODE="$(command -v opencode)"
fi

mkdir -p "$HOME/.config/bos" "$DATA_DIR"
install_bos_command
if [[ "$PLATFORM" == "linux" && -n "${BOS_VLLM_BIN:-}" ]]; then
  CONFIG="$HOME/.config/bos/config.json"
  [[ -f "$CONFIG" ]] || print -r -- '{"selected_model":"default"}' > "$CONFIG"
  jq --arg bin "$BOS_VLLM_BIN" '.vllm_bin=$bin' "$CONFIG" > "$CONFIG.next"
  mv "$CONFIG.next" "$CONFIG"
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
