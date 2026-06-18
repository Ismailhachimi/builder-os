#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h}"
BIN_DIR="$HOME/.local/bin"
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
MODEL_PLATFORM="$PLATFORM"
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

is_dgx_spark() {
  [[ "$PLATFORM" == "linux" && "$ARCH" == "aarch64" ]] || return 1
  has nvidia-smi || return 1
  nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -Eq '(^|[[:space:]])(NVIDIA )?GB10([[:space:]]|$)|DGX Spark'
}

is_dgx_spark && MODEL_PLATFORM="linux-spark"

shell_quote() {
  local value="$1"
  printf "%q" "$value"
}

env_has_key() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 1
  grep -Eq "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$file"
}

env_has_value() {
  local key="$1" file="$2"
  local value=""
  [[ -f "$file" ]] || return 1
  value="$(sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=[[:space:]]*//p" "$file" | tail -1)"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  [[ -n "$value" ]]
}

env_set_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local assignment
  local tmp line replaced=0

  assignment="$key=$(shell_quote "$value")"
  tmp="$file.tmp.$$"

  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if (( ! replaced )) && [[ "$line" =~ "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" ]]; then
        print -r -- "$assignment" >> "$tmp"
        replaced=1
      else
        print -r -- "$line" >> "$tmp"
      fi
    done < "$file"
  fi

  if (( ! replaced )); then
    [[ -s "$tmp" ]] && print >> "$tmp"
    print -r -- "$assignment" >> "$tmp"
  fi

  mv "$tmp" "$file"
}

setup_local_env() {
  local env_file="$ROOT/.env"
  local example_file="$ROOT/.env.example"
  local hf_token=""
  local created_env=0

  if [[ ! -f "$env_file" ]]; then
    if [[ -f "$example_file" ]]; then
      cp "$example_file" "$env_file"
    else
      print -r -- "HF_TOKEN=" > "$env_file"
    fi
    created_env=1
  fi

  if env_has_value HF_TOKEN "$env_file"; then
    info "Using Hugging Face token from .env for model downloads."
    return 0
  fi

  if (( ! created_env )) && env_has_key HF_TOKEN "$env_file"; then
    info "No Hugging Face token configured. You can add one later in .env as HF_TOKEN=hf_..."
    return 0
  fi

  if [[ ! -t 0 ]]; then
    env_set_key "$env_file" HF_TOKEN ""
    info "Created .env with an empty HF_TOKEN. Add a token later for faster model downloads."
    return 0
  fi

  print
  print -r -- "Hugging Face token (optional)"
  print -r -- "A token can make first model downloads faster and more reliable."
  print -r -- "Press Enter to skip; you can add HF_TOKEN=hf_... to .env later."
  read -rs "hf_token?HF_TOKEN: "
  print

  if [[ -n "$hf_token" ]]; then
    env_set_key "$env_file" HF_TOKEN "$hf_token"
    info "Saved HF_TOKEN in .env. This file is ignored by git."
  else
    env_set_key "$env_file" HF_TOKEN ""
    info "Saved an empty HF_TOKEN in .env. Add a token there later if downloads are slow or gated."
  fi
}

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
    if [[ "$MODEL_PLATFORM" != "linux-spark" ]]; then
      python3 -m venv --help >/dev/null 2>&1 || missing+=(python3-venv)
      [[ -f "$(python3 - <<'PY'
import sysconfig
print(sysconfig.get_config_var("INCLUDEPY") + "/Python.h")
PY
)" ]] || missing+=(python3-dev)
    fi
  else
    has python3 || missing+=(python3)
    if [[ "$MODEL_PLATFORM" != "linux-spark" ]]; then
      python3 - <<'PY' >/dev/null 2>&1 || missing+=(python3-devel)
import pathlib
import sysconfig

raise SystemExit(0 if pathlib.Path(sysconfig.get_config_var("INCLUDEPY"), "Python.h").exists() else 1)
PY
    fi
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

  info "Installing vLLM support tools into $vllm_venv..."
  "$vllm_venv/bin/python" -m pip install --upgrade ninja ||
    die "Could not install vLLM support tools into $vllm_venv."

  if [[ ! -x "$runtime_bin" ]]; then
    info "Installing vLLM into $vllm_venv..."
    "$vllm_venv/bin/python" -m pip install --upgrade vllm ||
      die "vLLM installation failed. Check the pip output above, or set BOS_VLLM_BIN to a compatible local vLLM executable."
  fi

  [[ -x "$runtime_bin" ]] ||
    die "vLLM installation completed, but $runtime_bin was not created."
}

ensure_linux_vllm_support_tools() {
  local runtime_bin="$1"
  local python_bin="${runtime_bin:h}/python"
  [[ -x "$python_bin" ]] || return 0

  "$python_bin" - <<'PY' >/dev/null 2>&1 && return 0
from pathlib import Path
import sys

sys.exit(0 if (Path(sys.executable).parent / "ninja").exists() else 1)
PY

  info "Installing vLLM support tools into ${runtime_bin:h:h}..."
  "$python_bin" -m pip install --upgrade ninja ||
    die "Could not install vLLM support tools into ${runtime_bin:h:h}."
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

install_linux_ollama() {
  if ! has ollama; then
    info "Installing Ollama for DGX Spark..."
    curl -fsSL https://ollama.com/install.sh | sh
  fi
}

validate_linux_ollama() {
  has ollama || install_linux_ollama
  has ollama || die "Ollama is not available. Install Ollama, then rerun ./install.sh."
  info "Validating Ollama runtime..."
  ollama --version >/dev/null 2>&1 ||
    die "Ollama was found, but 'ollama --version' failed."
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

  ensure_linux_vllm_support_tools "$runtime_bin"

  export BOS_VLLM_BIN="$runtime_bin"
}

case "$PLATFORM" in
  darwin) install_macos_packages ;;
  linux)
    install_linux_packages
    install_linux_opencode
    has systemctl || die "systemd is required for the Linux model service."
    if [[ "$MODEL_PLATFORM" == "linux-spark" ]]; then
      validate_linux_ollama
    else
      validate_linux_vllm
    fi
    ;;
esac

if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  OPENCODE="$HOME/.opencode/bin/opencode"
else
  OPENCODE="$(command -v opencode)"
fi

mkdir -p "$HOME/.config/bos" "$DATA_DIR"
install_bos_command
setup_local_env
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
BOS_ROOT="$ROOT" BOS_CONFIG_HOME="$HOME/.config/bos" BOS_DATA_HOME="$DATA_DIR" BOS_MLX_VENV="$VENV" BOS_MODEL_PLATFORM="$MODEL_PLATFORM" "$ROOT/bin/bos" doctor

if [[ -t 0 ]]; then
  print
  print -n "Download the default local model now? [Y/n]: "
  read -r fetch_model
  if [[ "${fetch_model:l}" != "n" ]]; then
    BOS_ROOT="$ROOT" BOS_CONFIG_HOME="$HOME/.config/bos" BOS_DATA_HOME="$DATA_DIR" BOS_MLX_VENV="$VENV" BOS_MODEL_PLATFORM="$MODEL_PLATFORM" "$ROOT/bin/bos" model fetch
  else
    info "Skipped model download. Run later: bos model fetch"
  fi
else
  info "Skipping model download in non-interactive install. Run later: bos model fetch"
fi

cat <<EOF

Builder OS is installed for $PLATFORM/$ARCH$([[ "$MODEL_PLATFORM" == "linux-spark" ]] && echo " (DGX Spark)" || true).

1. Open a new terminal, or run:
     export PATH="\$HOME/.local/bin:\$PATH"

2. Download the recommended local model:
     bos model fetch

3. Start the local model:
     bos start

   If first downloads are slow or gated, add a Hugging Face token later:
     $ROOT/.env

4. Open the current project in the coding agent:
     bos open .

Useful commands:
  bos status
  bos top
  bos init my-app
  bos model fetch
  bos stop
EOF
