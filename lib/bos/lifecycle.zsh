#!/bin/zsh

source "$BOS_ROOT/lib/bos/service.zsh"

bos_start_cache_progress_line() {
  local profile="$1" cache_name cache_path size incomplete_count
  cache_name="$(bos_profile_value "$profile" cache)"
  [[ -n "$cache_name" ]] || return 1
  cache_path="$HOME/.cache/huggingface/hub/$cache_name"
  [[ -d "$cache_path" ]] || {
    print -r -- "Downloading model weights: cache not created yet"
    return 0
  }
  incomplete_count="$(find "$cache_path" -name '*.incomplete' -print 2>/dev/null | wc -l | tr -d ' ')"
  (( incomplete_count > 0 )) || return 1
  size="$(du -sh "$cache_path" 2>/dev/null | awk '{print $1}')"
  size="${size:-unknown size}"
  print -r -- "Downloading model weights: $size cached, $incomplete_count partial files"
}

bos_start_ollama_progress_line() {
  local line retry_count
  [[ "$(bos_profile_value "$1" runtime)" == "ollama" ]] || return 1

  retry_count="$(grep -c 'Ollama pull failed; retrying' "$BOS_LOG_DIR/model.log" 2>/dev/null || true)"
  if (( retry_count > 0 )); then
    print -r -- "Ollama registry connection dropped while fetching the manifest; retrying (${retry_count})"
    return 0
  fi

  line="$(tail -n 80 "$BOS_LOG_DIR/model.error.log" 2>/dev/null | grep -E 'pulling|verifying|writing|success' | tail -1 || true)"
  [[ -n "$line" ]] || return 1
  line="${line//$'\r'/}"
  line="${line//$'\n'/ }"
  (( ${#line} > 180 )) && line="${line[1,177]}..."
  print -r -- "$line"
}

bos_start_progress_line() {
  local profile="$1"
  local cache_line="" ollama_line=""
  ollama_line="$(bos_start_ollama_progress_line "$profile" 2>/dev/null || true)"
  [[ -n "$ollama_line" ]] && { print -r -- "$ollama_line"; return 0; }

  cache_line="$(bos_start_cache_progress_line "$profile" 2>/dev/null || true)"
  [[ -n "$cache_line" ]] && { print -r -- "$cache_line"; return 0; }

  local line=""
  line="$({
    [[ -f "$BOS_LOG_DIR/model.log" ]] && tail -n 80 "$BOS_LOG_DIR/model.log"
    [[ -f "$BOS_LOG_DIR/model.error.log" ]] && tail -n 40 "$BOS_LOG_DIR/model.error.log"
  } 2>/dev/null | grep -E 'Downloading|Loading|Starting|load model|loaded|pulling|verifying|writing|success|compil|ERROR|Error|Warning' | tail -1 || true)"
  line="${line//$'\r'/}"
  line="${line//$'\n'/ }"
  (( ${#line} > 180 )) && line="${line[1,177]}..."
  print -r -- "$line"
}

bos_start() {
  bos_ensure_dirs
  local profile="$(bos_selected_model)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model) profile="${2:-}"; shift 2 ;;
      *) bos_die "Unknown start option: $1"; return 1 ;;
    esac
  done
  bos_profile_exists "$profile" || { bos_die "Unknown model profile: $profile"; return 1; }
  bos_profile_supported "$profile" || { bos_die "$(bos_profile_value "$profile" unsupported_reason)"; return 1; }
  if ! bos_profile_cache_complete "$profile"; then
    bos_die "Model is not downloaded: $(bos_profile_value "$profile" model). Run: bos model fetch $profile"
    return 1
  fi

  local active="$(bos_active_profile)"
  if bos_health; then
    if [[ "$active" == "$profile" ]]; then
      bos_info "$profile is already running."
      return 0
    fi
    bos_die "A model is already running (${active:-unmanaged}). Use: bos restart --model $profile"
    return 1
  fi
  if bos_service_loaded; then
    bos_info "Restarting unhealthy model service..."
    bos_service_stop
    local stop_attempt
    for (( stop_attempt = 1; stop_attempt <= 60; stop_attempt++ )); do
      ! bos_service_loaded && break
      sleep 1
    done
    if bos_service_loaded; then
      bos_die "Existing model service did not stop. Run: bos stop"
      return 1
    fi
    rm -f "$BOS_STATE"
  fi
  if [[ -n "$(bos_model_pid)" ]]; then
    bos_die "Port $BOS_PORT is owned by an unmanaged process. Stop it before using BOS."
    return 1
  fi

  : > "$BOS_LOG_DIR/model.log"
  : > "$BOS_LOG_DIR/model.error.log"

  bos_service_start "$profile"
  bos_atomic_json "$BOS_STATE" "$(jq -n --arg profile "$profile" --arg runtime "$(bos_profile_value "$profile" runtime)" --arg platform "$BOS_MODEL_PLATFORM" --arg started "$(date -u +%FT%TZ)" '{profile:$profile,runtime:$runtime,platform:$platform,started_at:$started}')"

  bos_info "Starting $profile..."
  bos_info "Logs: $BOS_LOG_DIR"
  local attempt timeout="${BOS_START_TIMEOUT:-7200}"
  local progress_line="" last_progress_line=""
  [[ "$timeout" == <-> ]] || { bos_die "BOS_START_TIMEOUT must be an integer."; return 1; }
  for (( attempt = 1; attempt <= timeout; attempt++ )); do
    if bos_health; then
      bos_info "Ready: $BOS_ENDPOINT"
      return 0
    fi
    if (( attempt > 5 )) && ! bos_service_loaded; then
      bos_error "Model service stopped before it became ready."
      bos_logs --lines 40 --no-follow
      return 1
    fi
    if (( attempt % 10 == 0 )); then
      progress_line="$(bos_start_progress_line "$profile")"
      if [[ -n "$progress_line" && "$progress_line" != "$last_progress_line" ]]; then
        bos_info "Still starting: $progress_line"
        last_progress_line="$progress_line"
      else
        bos_info "Still starting... (${attempt}s elapsed)"
      fi
    fi
    sleep 1
  done
  progress_line="$(bos_start_cache_progress_line "$profile" 2>/dev/null || true)"
  [[ -n "$progress_line" ]] && bos_error "$progress_line"
  bos_error "Model did not become ready within $timeout seconds."
  bos_logs --lines 40 --no-follow
  return 1
}

bos_stop() {
  bos_ensure_dirs
  if bos_service_loaded; then
    bos_info "Stopping model service..."
    bos_service_stop
    local attempt timeout="${BOS_STOP_TIMEOUT:-60}"
    [[ "$timeout" == <-> ]] || { bos_die "BOS_STOP_TIMEOUT must be an integer."; return 1; }
    for (( attempt = 1; attempt <= timeout; attempt++ )); do
      if ! bos_service_loaded; then
        rm -f "$BOS_STATE"
        bos_info "Model service stopped."
        return 0
      fi
      (( attempt % 5 == 0 )) && bos_info "Still stopping... (${attempt}s elapsed)"
      sleep 1
    done
    bos_die "Model service did not stop within ${timeout}s. Check: systemctl --user status builder-os-model.service"
    return 1
  elif [[ -n "$(bos_model_pid)" ]]; then
    bos_die "Port $BOS_PORT is owned by an unmanaged process; BOS will not terminate it."
    return 1
  else
    rm -f "$BOS_STATE"
    bos_info "Model service is already stopped."
  fi
}

bos_restart() {
  local args=("$@")
  bos_stop
  bos_start "${args[@]}"
}

bos_status() {
  bos_ensure_dirs
  local selected="$(bos_selected_model)"
  local active="$(bos_active_profile)"
  local selected_name="$(bos_profile_value "$selected" name)"
  local selected_model="$(bos_profile_value "$selected" model)"
  local active_name="" active_model=""
  if [[ -n "$active" ]]; then
    active_name="$(bos_profile_value "$active" name)"
    active_model="$(bos_profile_value "$active" model)"
  fi
  local pid="$(bos_model_pid)"
  local health="stopped"
  bos_health && health="healthy"
  local rss="-" cpu="-" uptime="-" workers="0" metrics rss_kb
  if [[ -n "$pid" ]]; then
    metrics="$(bos_model_metrics "$pid")"
    read -r rss_kb cpu uptime workers <<< "$metrics"
    [[ -n "$rss_kb" ]] && rss="$(bos_format_bytes "$((rss_kb * 1024))")"
    rss="${rss:--}"
    cpu="${cpu:--}"
    uptime="${uptime:--}"
    workers="${workers:-0}"
  fi
  printf "%-18s %s (%s)\n" "Selected model:" "$selected" "$selected_name"
  printf "%-18s %s\n" "Selected ID:" "$selected_model"
  if [[ -n "$active" ]]; then
    printf "%-18s %s (%s)\n" "Active model:" "$active" "$active_name"
    printf "%-18s %s\n" "Active ID:" "$active_model"
  else
    printf "%-18s %s\n" "Active model:" "none"
  fi
  printf "%-18s %s\n" "Health:" "$health"
  printf "%-18s %s / %s\n" "Platform/runtime:" "$BOS_MODEL_PLATFORM" "$([[ -n "$active" ]] && bos_profile_value "$active" runtime || echo none)"
  printf "%-18s %s\n" "PID:" "${pid:-none}"
  printf "%-18s %s\n" "Workers:" "$workers"
  printf "%-18s %s\n" "Uptime:" "$uptime"
  printf "%-18s %s\n" "CPU:" "$cpu"
  printf "%-18s %s\n" "Service memory:" "$rss"
  printf "%-18s %s\n" "Endpoint:" "$BOS_ENDPOINT"
  printf "%-18s %s\n" "Logs:" "$BOS_LOG_DIR"
  local gpu="$(bos_gpu_metrics)"
  [[ -n "$gpu" ]] && printf "%-18s %s\n" "GPU used/total/util:" "$gpu"
  return 0
}

bos_logs() {
  bos_ensure_dirs
  local lines=80 follow="-f"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lines) lines="${2:-80}"; shift 2 ;;
      --no-follow) follow=""; shift ;;
      *) bos_die "Unknown logs option: $1"; return 1 ;;
    esac
  done
  touch "$BOS_LOG_DIR/model.log" "$BOS_LOG_DIR/model.error.log"
  tail ${follow:+$follow} -n "$lines" "$BOS_LOG_DIR/model.log" "$BOS_LOG_DIR/model.error.log"
}

bos_model_metrics() {
  local pid="$1"
  [[ -n "$pid" ]] || { print "0 0 - 0"; return 0; }
  ps -eo pid=,ppid=,rss=,%cpu=,etime= 2>/dev/null |
    awk -v root="$pid" '
      $1 == root {
        rss += $3
        cpu += $4
        uptime = $5
        found = 1
      }
      $2 == root {
        rss += $3
        cpu += $4
        workers += 1
      }
      END {
        if (!found) {
          print "0 0 - 0"
        } else {
          printf "%.0f %.1f %s %.0f\n", rss, cpu, uptime, workers
        }
      }
    '
}

bos_top_once() {
  local cpu_history="${1:-}" rss_history="${2:-}"
  local selected active selected_name active_name active_model pid health health_text
  local cpu="0" rss_kb="0" rss_bytes=0 uptime="-" workers="0" metrics total_bytes model_percent=0 free_percent="-" swap_total=0 swap_used=0 swap_percent=0 gpu=""

  selected="$(bos_selected_model)"
  active="$(bos_active_profile)"
  selected_name="$(bos_profile_value "$selected" name)"
  active_name="$([[ -n "$active" ]] && bos_profile_value "$active" name || echo "No active model")"
  active_model="$([[ -n "$active" ]] && bos_profile_value "$active" model || echo "Start one with: bos start")"
  pid="$(bos_model_pid)"
  health="stopped"
  bos_health && health="healthy"
  if [[ -n "$pid" ]]; then
    metrics="$(bos_model_metrics "$pid")"
    read -r rss_kb cpu uptime workers <<< "$metrics"
  fi
  cpu="${cpu:-0}"
  rss_kb="${rss_kb:-0}"
  uptime="${uptime:--}"
  workers="${workers:-0}"
  rss_bytes="$((rss_kb * 1024))"
  total_bytes="$(bos_total_memory_bytes)"
  (( total_bytes > 0 )) && model_percent="$((rss_bytes * 100 / total_bytes))"
  free_percent="$(bos_memory_free_percent)"
  free_percent="${free_percent:--}"
  read -r swap_total swap_used <<< "$(bos_swap_metrics_mb)"
  swap_total="${swap_total:-0}"
  swap_used="${swap_used:-0}"
  (( swap_total > 0 )) && swap_percent="$((swap_used * 100 / swap_total))"

  health_text="${health:u}"
  printf "%s+%s+%s\n" "$BOS_CYAN" "$(bos_repeat = "$((BOS_DASH_WIDTH - 2))")" "$BOS_RESET"
  bos_panel_line "BUILDER OS  |  LOCAL AGENT CONTROL PLANE  |  $(date '+%H:%M:%S')"
  printf "%s+%s+%s\n\n" "$BOS_CYAN" "$(bos_repeat = "$((BOS_DASH_WIDTH - 2))")" "$BOS_RESET"

  bos_panel_header "MODEL SERVICE"
  bos_panel_line "Health: [$health_text]   Profile: ${active:-none}   PID: ${pid:-none}   W:$workers   Up:$uptime"
  bos_panel_line "$active_name"
  bos_panel_line "$active_model"
  bos_panel_line "CPU   $(bos_bar "$cpu" 24) $(printf '%6s%%' "$cpu")   $(bos_sparkline "$cpu_history" 24)"
  bos_panel_line "RSS   $(bos_bar "$model_percent" 24) $(printf '%6s' "$(bos_format_bytes "$rss_bytes")") / $(bos_format_bytes "$total_bytes")   $(bos_sparkline "$rss_history" 24)"
  bos_panel_end
  echo

  bos_panel_header "SYSTEM MEMORY"
  bos_panel_line "Pressure headroom  $(bos_bar "${free_percent//[^0-9]/0}" 28) ${free_percent}% free"
  bos_panel_line "Swap used          $(bos_bar "$swap_percent" 28) $(printf '%.0f MB / %.0f MB' "$swap_used" "$swap_total")"
  gpu="$(bos_gpu_metrics)"
  [[ -n "$gpu" ]] && bos_panel_line "GPU                 used / total MiB / utilization: $gpu"
  bos_panel_line "Selected model: $selected ($selected_name)"
  bos_panel_end
  echo

  bos_panel_header "MODEL LIBRARY"
  if (( ${#BOS_DASH_MODEL_LINES} )); then
    for profile in "${BOS_DASH_MODEL_LINES[@]}"; do
      bos_panel_line "$profile"
    done
  else
    while IFS= read -r profile; do
      bos_panel_line "$(bos_dashboard_cache_line "$profile" "$selected" "$active")"
    done < <(jq -r '.profiles | keys[]' "$BOS_MODELS")
  fi
  bos_panel_end
  echo

  bos_panel_header "LATEST EVALUATION"
  bos_dashboard_eval_lines
  bos_panel_end
  printf "\n%sCtrl+C quit  |  bos logs  |  bos status  |  refresh: ${BOS_TOP_INTERVAL:-2}s%s\n" "$BOS_DIM" "$BOS_RESET"
}

bos_top() {
  source "$BOS_ROOT/lib/bos/dashboard.zsh"
  local once=0 interval=1 cpu rss pid rss_kb total_bytes model_percent selected active frame
  local -a cpu_history rss_history
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --once) once=1; shift ;;
      --interval) interval="${2:-1}"; shift 2 ;;
      *) bos_die "Unknown top option: $1"; return 1 ;;
    esac
  done
  [[ "$interval" == <-> || "$interval" == <->.<-> ]] || { bos_die "Top interval must be a number."; return 1; }
  typeset -g BOS_TOP_INTERVAL="$interval"
  bos_dashboard_setup
  selected="$(bos_selected_model)"
  active="$(bos_active_profile)"
  bos_dashboard_prepare_static "$selected" "$active"
  if (( ! once )); then
    bos_dashboard_enter
    trap 'bos_dashboard_leave' EXIT
    trap 'return 0' INT TERM
  fi
  while true; do
    pid="$(bos_model_pid)"
    cpu="0" rss_kb="0"
    if [[ -n "$pid" ]]; then
      read -r rss_kb cpu _ <<< "$(bos_model_metrics "$pid")"
    fi
    total_bytes="$(bos_total_memory_bytes)"
    model_percent=0
    (( total_bytes > 0 )) && model_percent="$((rss_kb * 1024 * 100 / total_bytes))"
    cpu_history+=("${cpu:-0}")
    rss_history+=("$model_percent")
    (( ${#cpu_history} > 24 )) && cpu_history=("${cpu_history[@]: -24}")
    (( ${#rss_history} > 24 )) && rss_history=("${rss_history[@]: -24}")
    frame="$(bos_top_once "${(j: :)cpu_history}" "${(j: :)rss_history}")"
    (( ! once )) && bos_dashboard_home
    printf "%s\n" "$frame"
    (( once )) && return 0
    bos_dashboard_finish_frame
    sleep "$interval"
  done
}
