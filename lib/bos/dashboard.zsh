#!/bin/zsh

typeset -g BOS_DASH_WIDTH=80
typeset -g BOS_DASH_COLOR=0
typeset -g BOS_CYAN="" BOS_GREEN="" BOS_YELLOW="" BOS_RED="" BOS_DIM="" BOS_RESET=""
typeset -ga BOS_DASH_MODEL_LINES

bos_dashboard_setup() {
  local width="${COLUMNS:-}"
  [[ "$width" == <-> ]] || width="$(tput cols 2>/dev/null || echo 80)"
  (( width < 80 )) && width=80
  (( width > 110 )) && width=110
  BOS_DASH_WIDTH="$width"

  if [[ -t 1 ]] && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    BOS_DASH_COLOR=1
    BOS_CYAN=$'\e[36m'
    BOS_GREEN=$'\e[32m'
    BOS_YELLOW=$'\e[33m'
    BOS_RED=$'\e[31m'
    BOS_DIM=$'\e[2m'
    BOS_RESET=$'\e[0m'
  fi
}

bos_repeat() {
  local character="$1" count="${2:-0}"
  (( count <= 0 )) && return 0
  printf "%${count}s" "" | tr ' ' "$character"
}

bos_panel_header() {
  local title=" $1 " fill
  fill="$(bos_repeat - "$((BOS_DASH_WIDTH - ${#title} - 2))")"
  printf "%s+%s%s+%s\n" "$BOS_CYAN" "$title" "$fill" "$BOS_RESET"
}

bos_panel_line() {
  local text="$1" inner="$((BOS_DASH_WIDTH - 4))"
  (( ${#text} > inner )) && text="${text[1,$inner]}"
  printf "| %-*s |\n" "$inner" "$text"
}

bos_panel_end() {
  printf "%s+%s+%s\n" "$BOS_CYAN" "$(bos_repeat - "$((BOS_DASH_WIDTH - 2))")" "$BOS_RESET"
}

bos_bar() {
  local percent="${1:-0}" width="${2:-20}" filled empty
  [[ "$percent" == <-> || "$percent" == <->.<-> ]] || percent=0
  percent="${percent%%.*}"
  (( percent < 0 )) && percent=0
  (( percent > 100 )) && percent=100
  filled="$((percent * width / 100))"
  empty="$((width - filled))"
  printf "[%s%s]" "$(bos_repeat '#' "$filled")" "$(bos_repeat . "$empty")"
}

bos_sparkline() {
  local input="${1:-}" width="${2:-28}" value index output="" levels="._:-=+*#"
  local -a values
  values=(${=input})
  (( ${#values} > width )) && values=("${values[@]: -$width}")
  for value in "${values[@]}"; do
    [[ "$value" == <-> || "$value" == <->.<-> ]] || value=0
    (( value > 100 )) && value=100
    (( value < 0 )) && value=0
    index="$((value / 13 + 1))"
    (( index > 8 )) && index=8
    output+="${levels[$index]}"
  done
  printf "%-${width}s" "$output"
}

bos_metric_color() {
  local value="${1:-0}"
  if (( value >= 90 )); then
    print -nr -- "$BOS_RED"
  elif (( value >= 70 )); then
    print -nr -- "$BOS_YELLOW"
  else
    print -nr -- "$BOS_GREEN"
  fi
}

bos_dashboard_cache_line() {
  local profile="$1" selected="$2" active="$3"
  local name cache_path size="not cached" flags=""
  name="$(bos_profile_value "$profile" name)"
  cache_path="$HOME/.cache/huggingface/hub/$(bos_profile_value "$profile" cache)"
  [[ -d "$cache_path" ]] && size="$(du -sh "$cache_path" 2>/dev/null | awk '{print $1}')"
  [[ "$profile" == "$selected" ]] && flags+=" selected"
  [[ "$profile" == "$active" ]] && flags+=" active"
  printf "%-12s %-20s %-5s %8s%s" "$profile" "$name" "$(bos_profile_value "$profile" runtime)" "$size" "$flags"
}

bos_dashboard_prepare_static() {
  local selected="$1" active="$2" profile
  BOS_DASH_MODEL_LINES=()
  while IFS= read -r profile; do
    BOS_DASH_MODEL_LINES+=("$(bos_dashboard_cache_line "$profile" "$selected" "$active")")
  done < <(jq -r '.profiles | keys[]' "$BOS_MODELS")
}

bos_dashboard_enter() {
  [[ -t 1 ]] || return 0
  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  tput clear 2>/dev/null || true
}

bos_dashboard_home() {
  [[ -t 1 ]] && tput cup 0 0 2>/dev/null || true
}

bos_dashboard_finish_frame() {
  [[ -t 1 ]] && tput ed 2>/dev/null || true
}

bos_dashboard_leave() {
  [[ -t 1 ]] || return 0
  tput cnorm 2>/dev/null || true
  tput rmcup 2>/dev/null || true
}

bos_dashboard_eval_lines() {
  local results="$BOS_ROOT/benchmark/RESULTS.md" total prompt generation peak
  [[ -f "$results" ]] || { bos_panel_line "No evaluation results yet. Run: bos eval compare default coder-next"; return; }
  total="$(grep -E '^\| \*\*Total' "$results" 2>/dev/null | sed -E 's/^\| \*\*Total\*\* \| \*\*([^*]+)\*\* \| \*\*([^*]+)\*\* \|.*/default: \1   coder-next: \2/')"
  prompt="$(grep -E '^\| Prompt processing' "$results" 2>/dev/null | sed -E 's/^\| Prompt processing \| ([^|]+) \| ([^|]+) \|.*/Prompt: \1 | \2/')"
  generation="$(grep -E '^\| Generation' "$results" 2>/dev/null | sed -E 's/^\| Generation \| ([^|]+) \| ([^|]+) \|.*/Generation: \1 | \2/')"
  peak="$(grep -E '^\| MLX peak memory' "$results" 2>/dev/null | sed -E 's/^\| MLX peak memory \| ([^|]+) \| ([^|]+) \|.*/Peak memory: \1 | \2/')"
  bos_panel_line "${total:-Evaluation results available}"
  bos_panel_line "${prompt:-Prompt speed unavailable}"
  bos_panel_line "${generation:-Generation speed unavailable}"
  bos_panel_line "${peak:-Peak memory unavailable}"
}
