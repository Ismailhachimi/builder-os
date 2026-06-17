#!/bin/zsh

bos_models() {
  bos_ensure_dirs
  local selected="$(bos_selected_model)" active="$(bos_active_profile)"
  local profile cache expected model runtime cached availability
  printf "%-14s %-9s %-9s %-8s %-10s %-7s %s\n" PROFILE SELECTED ACTIVE RUNTIME STATUS MEMORY MODEL
  jq -r '.profiles | keys[]' "$BOS_MODELS" |
    while IFS= read -r profile; do
      cache="$(bos_profile_value "$profile" cache)"
      expected="$(bos_profile_value "$profile" expected_memory_gb)"
      model="$(bos_profile_value "$profile" model)"
      runtime="$(bos_profile_value "$profile" runtime)"
      cached="no"
      availability=""
      bos_profile_cache_complete "$profile" && cached="yes"
      availability="$([[ "$(bos_profile_value "$profile" supported)" == "false" ]] && echo unavailable || echo "$cached")"
      printf "%-14s %-9s %-9s %-8s %-10s %-7s %s\n" "$profile" "$([[ "$profile" == "$selected" ]] && echo yes || echo no)" "$([[ "$profile" == "$active" ]] && echo yes || echo no)" "$runtime" "$availability" "${expected}GB" "$model"
    done
}

bos_ollama_wait() {
  local attempt
  for (( attempt = 1; attempt <= 60; attempt++ )); do
    curl --silent --fail --max-time 2 "http://127.0.0.1:$BOS_PORT/api/tags" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

bos_ollama_pull_with_retries() {
  local runtime_bin="$1" model="$2" pull_attempt pull_status delay
  for (( pull_attempt = 1; pull_attempt <= 30; pull_attempt++ )); do
    OLLAMA_HOST="127.0.0.1:$BOS_PORT" "$runtime_bin" pull "$model" && return 0
    pull_status=$?
    (( pull_attempt == 30 )) && return "$pull_status"
    (( pull_attempt < 6 )) && delay=$((pull_attempt * 10)) || delay=60
    bos_warn "Ollama pull failed; retrying (${pull_attempt}/30) in ${delay}s..."
    sleep "$delay"
  done
  return 1
}

bos_model_fetch() {
  local profile="${1:-$(bos_selected_model)}"
  local runtime model cache cache_path runtime_bin python_bin ollama_pid=""
  bos_ensure_dirs
  bos_profile_exists "$profile" || { bos_die "Unknown model profile: $profile"; return 1; }
  bos_profile_supported "$profile" || { bos_die "$(bos_profile_value "$profile" unsupported_reason)"; return 1; }

  runtime="$(bos_profile_value "$profile" runtime)"
  model="$(bos_profile_value "$profile" model)"
  cache="$(bos_profile_value "$profile" cache)"
  [[ -n "$cache" ]] && cache_path="$HOME/.cache/huggingface/hub/$cache" || cache_path=""

  if bos_profile_cache_complete "$profile"; then
    bos_info "$profile is already cached: $model"
    return 0
  fi

  if bos_service_loaded; then
    bos_die "Stop the model service before fetching weights: bos stop"
    return 1
  fi

  case "$runtime" in
    ollama)
      runtime_bin="$(bos_ollama_bin)"
      [[ -x "$runtime_bin" ]] || { bos_die "Ollama not found. Run: $BOS_ROOT/install.sh"; return 1; }
      if ! curl --silent --fail --max-time 2 "http://127.0.0.1:$BOS_PORT/api/tags" >/dev/null 2>&1; then
        [[ -z "$(bos_model_pid)" ]] || { bos_die "Port $BOS_PORT is owned by an unmanaged process. Stop it before fetching."; return 1; }
        bos_info "Starting temporary Ollama server..."
        OLLAMA_HOST="127.0.0.1:$BOS_PORT" "$runtime_bin" serve >> "$BOS_LOG_DIR/model.log" 2>> "$BOS_LOG_DIR/model.error.log" &
        ollama_pid="$!"
        trap '[[ -n "$ollama_pid" ]] && kill "$ollama_pid" >/dev/null 2>&1 || true' EXIT
        bos_ollama_wait || { bos_die "Temporary Ollama server did not become ready."; return 1; }
      fi
      bos_info "Fetching $profile: $model"
      bos_ollama_pull_with_retries "$runtime_bin" "$model" || {
        bos_die "Ollama model fetch failed. Rerun: bos model fetch $profile"
        return 1
      }
      [[ -n "$ollama_pid" ]] && { kill "$ollama_pid" >/dev/null 2>&1 || true; wait "$ollama_pid" >/dev/null 2>&1 || true; ollama_pid=""; }
      trap - EXIT
      bos_info "Fetched $profile."
      return 0
      ;;
    vllm)
      runtime_bin="$(bos_vllm_bin)"
      [[ -x "$runtime_bin" ]] || { bos_die "vLLM not found. Install it or set BOS_VLLM_BIN."; return 1; }
      python_bin="${runtime_bin:h}/python"
      [[ -x "$python_bin" ]] || python_bin="$(command -v python3 2>/dev/null || true)"
      [[ -n "$python_bin" && -x "$python_bin" ]] || { bos_die "Python is required to fetch Hugging Face model weights."; return 1; }
      ;;
    mlx)
      python_bin="$BOS_MLX_VENV/bin/python"
      [[ -x "$python_bin" ]] || python_bin="$(command -v python3 2>/dev/null || true)"
      [[ -n "$python_bin" && -x "$python_bin" ]] || { bos_die "Python is required to fetch Hugging Face model weights."; return 1; }
      ;;
    *) bos_die "Unsupported runtime: $runtime"; return 1 ;;
  esac

  bos_info "Fetching $profile: $model"
  bos_info "Cache: $HOME/.cache/huggingface/hub/$cache"
  bos_info "This resumes partial downloads and uses HF_TOKEN from .env when set."

  HF_HOME="$HOME/.cache/huggingface" HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}" "$python_bin" -c '
import os
import sys
from huggingface_hub import snapshot_download

model = sys.argv[1]
token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN") or None
snapshot_download(
    repo_id=model,
    cache_dir=os.path.expanduser("~/.cache/huggingface/hub"),
    token=token,
    max_workers=1,
)
' "$model" || {
    bos_die "Model fetch failed. Check your network/HF_TOKEN and rerun: bos model fetch $profile"
    return 1
  }

  if bos_profile_cache_complete "$profile"; then
    bos_info "Fetched $profile."
  else
    bos_die "Fetch ended but the cache is still incomplete: $cache_path"
    return 1
  fi
}

bos_model() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    fetch)
      bos_model_fetch "${1:-}"
      ;;
    select)
      local profile="${1:-}"
      [[ -n "$profile" ]] || { bos_die "Usage: bos model select <profile>"; return 1; }
      bos_profile_exists "$profile" || { bos_die "Unknown model profile: $profile"; return 1; }
      bos_profile_supported "$profile" || { bos_die "$(bos_profile_value "$profile" unsupported_reason)"; return 1; }
      bos_ensure_dirs
      bos_atomic_json "$BOS_USER_CONFIG" "$(jq --arg profile "$profile" '.selected_model=$profile' "$BOS_USER_CONFIG")"
      bos_info "Selected default model: $profile"
      local active="$(bos_active_profile)"
      [[ -n "$active" && "$active" != "$profile" ]] && bos_info "Active model remains $active. Apply with: bos restart"
      return 0
      ;;
    *) bos_die "Usage: bos model select <profile> | bos model fetch [profile]"; return 1 ;;
  esac
}
