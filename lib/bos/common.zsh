#!/bin/zsh

set -euo pipefail

: "${BOS_ROOT:?BOS_ROOT must point to the Builder OS repository}"

[[ -d /opt/homebrew/bin ]] && export PATH="$PATH:/opt/homebrew/bin"

BOS_CONFIG_HOME="${BOS_CONFIG_HOME:-$HOME/.config/bos}"
BOS_PLATFORM="${BOS_PLATFORM:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
case "$BOS_PLATFORM" in
  darwin) BOS_DATA_HOME="${BOS_DATA_HOME:-$HOME/Library/Application Support/BuilderOS}" ;;
  linux) BOS_DATA_HOME="${BOS_DATA_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/builder-os}" ;;
  *) BOS_DATA_HOME="${BOS_DATA_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/builder-os}" ;;
esac
BOS_RUNTIME_DIR="$BOS_DATA_HOME/runtime"
BOS_LOG_DIR="$BOS_DATA_HOME/logs"
BOS_MLX_VENV="${BOS_MLX_VENV:-$BOS_DATA_HOME/venv}"
BOS_LAUNCHD_LABEL="com.builderos.model"
BOS_PLIST="$BOS_RUNTIME_DIR/$BOS_LAUNCHD_LABEL.plist"
BOS_SYSTEMD_UNIT="$BOS_RUNTIME_DIR/builder-os-model.service"
BOS_SERVICE_SCRIPT="$BOS_RUNTIME_DIR/model-service.zsh"
BOS_STATE="$BOS_RUNTIME_DIR/model.json"
BOS_USER_CONFIG="$BOS_CONFIG_HOME/config.json"
BOS_PROJECTS="$BOS_CONFIG_HOME/projects.json"
BOS_MODELS="$BOS_ROOT/config/models.json"
BOS_PORT="${BOS_PORT:-8080}"
BOS_ENDPOINT="http://127.0.0.1:$BOS_PORT/v1"
if [[ -n "${OPENCODE_BIN:-}" ]]; then
  BOS_OPENCODE_BIN="$OPENCODE_BIN"
elif [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  BOS_OPENCODE_BIN="$HOME/.opencode/bin/opencode"
else
  BOS_OPENCODE_BIN="$(command -v opencode 2>/dev/null || true)"
fi

bos_info() { print -r -- "$*"; }
bos_warn() { print -u2 -r -- "Warning: $*"; }
bos_error() { print -u2 -r -- "Error: $*"; }
bos_die() { bos_error "$*"; return 1; }
bos_has() { command -v "$1" >/dev/null 2>&1; }

bos_ensure_dirs() {
  mkdir -p "$BOS_CONFIG_HOME" "$BOS_RUNTIME_DIR" "$BOS_LOG_DIR" "$BOS_CONFIG_HOME/templates"
  [[ -f "$BOS_USER_CONFIG" ]] || print -r -- '{"selected_model":"default"}' > "$BOS_USER_CONFIG"
  [[ -f "$BOS_PROJECTS" ]] || print -r -- '{"projects":[]}' > "$BOS_PROJECTS"
}

bos_require() {
  bos_has "$1" || bos_die "Required command not found: $1"
}

bos_atomic_json() {
  local target="$1"
  local content="$2"
  local tmp="$target.tmp.$$"
  print -r -- "$content" > "$tmp"
  mv "$tmp" "$target"
}

bos_profile_exists() {
  jq -e --arg profile "$1" '.profiles[$profile] != null' "$BOS_MODELS" >/dev/null
}

bos_profile_value() {
  jq -r --arg profile "$1" --arg platform "$BOS_PLATFORM" --arg key "$2" '
    if (.profiles[$profile].platforms[$platform] // {} | has($key)) then
      .profiles[$profile].platforms[$platform][$key]
    elif (.profiles[$profile] // {} | has($key)) then
      .profiles[$profile][$key]
    else
      empty
    end
  ' "$BOS_MODELS"
}

bos_profile_supported() {
  [[ "$(bos_profile_value "$1" supported)" != "false" ]]
}

bos_selected_model() {
  bos_ensure_dirs
  jq -r '.selected_model // "default"' "$BOS_USER_CONFIG"
}

bos_active_profile() {
  [[ -f "$BOS_STATE" ]] && jq -r '.profile // empty' "$BOS_STATE" 2>/dev/null || true
}

bos_health() {
  curl --silent --fail --max-time 2 "$BOS_ENDPOINT/models" >/dev/null 2>&1
}

bos_service_loaded() {
  case "$BOS_PLATFORM" in
    darwin) launchctl print "gui/$(id -u)/$BOS_LAUNCHD_LABEL" >/dev/null 2>&1 ;;
    linux) systemctl --user is-active --quiet builder-os-model.service ;;
    *) return 1 ;;
  esac
}

bos_model_pid() {
  if bos_has lsof; then
    lsof -tiTCP:"$BOS_PORT" -sTCP:LISTEN 2>/dev/null | head -1
  elif bos_has fuser; then
    fuser "$BOS_PORT/tcp" 2>/dev/null | awk '{print $1}'
  fi
}

bos_format_bytes() {
  local bytes="${1:-0}"
  awk -v bytes="$bytes" 'BEGIN {
    split("B KB MB GB TB", u, " ");
    i=1; while (bytes >= 1024 && i < 5) { bytes/=1024; i++ }
    printf "%.1f %s", bytes, u[i]
  }'
}

bos_project_env() {
  export OPENCODE_CONFIG="$BOS_ROOT/opencode.json"
  export OPENCODE_DISABLE_AUTOUPDATE=1
  export OPENCODE_DISABLE_SHARE=1
  export HTTP_PROXY="http://127.0.0.1:9"
  export HTTPS_PROXY="http://127.0.0.1:9"
  export ALL_PROXY="http://127.0.0.1:9"
  export NO_PROXY="localhost,127.0.0.1"
}

bos_total_memory_bytes() {
  case "$BOS_PLATFORM" in
    darwin) sysctl -n hw.memsize 2>/dev/null || echo 0 ;;
    linux) awk '/MemTotal:/ {print $2 * 1024}' /proc/meminfo 2>/dev/null || echo 0 ;;
    *) echo 0 ;;
  esac
}

bos_memory_free_percent() {
  case "$BOS_PLATFORM" in
    darwin)
      { memory_pressure 2>/dev/null || true; } |
        awk -F': ' '/System-wide memory free percentage/ {gsub(/%/,"",$2); print $2}' | tail -1
      ;;
    linux)
      awk '/MemTotal:/ {total=$2} /MemAvailable:/ {available=$2} END {if(total) printf "%.0f", available*100/total}' /proc/meminfo 2>/dev/null
      ;;
  esac
}

bos_swap_metrics_mb() {
  case "$BOS_PLATFORM" in
    darwin)
      sysctl vm.swapusage 2>/dev/null |
        awk '{for(i=1;i<=NF;i++){if($i=="total"){gsub("M","",$(i+2)); total=$(i+2)}; if($i=="used"){gsub("M","",$(i+2)); used=$(i+2)}}} END {print total+0, used+0}'
      ;;
    linux)
      awk '/SwapTotal:/ {total=$2/1024} /SwapFree:/ {free=$2/1024} END {printf "%.0f %.0f", total, total-free}' /proc/meminfo 2>/dev/null
      ;;
    *) echo "0 0" ;;
  esac
}

bos_gpu_metrics() {
  if bos_has nvidia-smi; then
    nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1
  fi
}

bos_vllm_bin() {
  local configured=""
  if [[ -n "${BOS_VLLM_BIN:-}" ]]; then
    print -r -- "$BOS_VLLM_BIN"
  elif [[ -f "$BOS_USER_CONFIG" ]]; then
    configured="$(jq -r '.vllm_bin // empty' "$BOS_USER_CONFIG")"
    [[ -n "$configured" ]] && print -r -- "$configured" || command -v vllm 2>/dev/null || true
  else
    command -v vllm 2>/dev/null || true
  fi
}

bos_help() {
  cat <<'EOF'
Builder OS - local agentic development control plane

Usage: bos <command> [options]

Lifecycle:
  start [--model PROFILE]   Start the local model service
  stop                      Stop the local model service
  restart [--model PROFILE] Restart the service
  status                    Show model and machine status
  logs [--lines N] [--no-follow]
  top [--once] [--interval N]
                            Live model and machine dashboard

Projects:
  init NAME [--template web] [--path DIR] [--orm drizzle|prisma] [--yes]
  open NAME|PATH|. [-- OPENCODE_ARGS...]
  projects
  project register [PATH|.] [--name NAME] [--type TYPE]
  sessions [--project NAME|PATH|.] [--all|--projects] [--select] [--limit N] [--json]
  session list [--project NAME|PATH|.] [--all|--projects] [--select] [--limit N] [--json]
  session resume [SESSION_ID] [--project NAME|PATH|.] [--all] [--latest]
  session delete SESSION_ID [--yes]

Models and evaluation:
  models
  model select PROFILE
  eval compare PROFILE PROFILE [--yes]

Other:
  opencode [ARGS...]          Advanced OpenCode passthrough
  doctor
  version
EOF
}

bos_doctor() {
  bos_ensure_dirs
  local failed=0
  case "$BOS_PLATFORM" in
    darwin) echo "ok    macOS ($(uname -m))" ;;
    linux) echo "ok    Linux ($(uname -m))" ;;
    *) echo "fail  Unsupported platform: $BOS_PLATFORM"; failed=1 ;;
  esac
  local service_command="$([[ "$BOS_PLATFORM" == "darwin" ]] && echo launchctl || echo systemctl)"
  for command_name in jq curl "$service_command" git column; do
    if bos_has "$command_name"; then
      printf "ok    %s\n" "$command_name"
    else
      printf "fail  %s\n" "$command_name"
      failed=1
    fi
  done
  local selected runtime runtime_bin
  selected="$(bos_selected_model)"
  runtime="$(bos_profile_value "$selected" runtime)"
  case "$runtime" in
    mlx)
      [[ -x "$BOS_MLX_VENV/bin/mlx_lm.server" ]] && echo "ok    MLX runtime" || { echo "fail  MLX runtime; rerun install.sh"; failed=1; }
      ;;
    vllm)
      runtime_bin="$(bos_vllm_bin)"
      [[ -x "$runtime_bin" ]] && echo "ok    vLLM runtime" || { echo "fail  vLLM runtime; install vLLM or set BOS_VLLM_BIN"; failed=1; }
      bos_has nvidia-smi && echo "ok    GPU metrics (nvidia-smi)" || echo "info  optional GPU metrics unavailable"
      ;;
    *) echo "fail  Unsupported runtime for $selected: ${runtime:-none}"; failed=1 ;;
  esac
  [[ -x "$BOS_OPENCODE_BIN" ]] && echo "ok    OpenCode" || { echo "fail  OpenCode"; failed=1; }
  jq empty "$BOS_MODELS" "$BOS_USER_CONFIG" "$BOS_PROJECTS" >/dev/null && echo "ok    JSON configuration" || failed=1
  bos_health && echo "ok    local model endpoint" || echo "info  local model endpoint is stopped"
  return "$failed"
}
