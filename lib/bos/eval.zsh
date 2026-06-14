#!/bin/zsh

bos_eval_summary() {
  local profile="$1"
  local behavior runtime
  behavior="$(find "$BOS_ROOT/benchmark/results" -maxdepth 1 -type d -name "*-$profile" | sort | tail -1)"
  runtime="$(find "$BOS_ROOT/benchmark/results" -maxdepth 1 -type d -name "*-$profile-runtime" | sort | tail -1)"
  local passed=0 total=0 seconds=0 prompt="-" generation="-" memory="-"
  if [[ -f "$behavior/summary.tsv" ]]; then
    passed="$(awk -F'\t' 'NR>1 && $3=="pass"{n++} END{print n+0}' "$behavior/summary.tsv")"
    total="$(awk 'END{print NR-1}' "$behavior/summary.tsv")"
    seconds="$(awk -F'\t' 'NR>1{s+=$2} END{print s+0}' "$behavior/summary.tsv")"
  fi
  if [[ -f "$runtime/generation.log" ]]; then
    prompt="$(grep 'Prompt:' "$runtime/generation.log" | sed -E 's/.* ([0-9.]+|unavailable) tokens-per-sec.*/\1/' | tail -1)"
    generation="$(grep 'Generation:' "$runtime/generation.log" | sed -E 's/.* ([0-9.]+) tokens-per-sec.*/\1/' | tail -1)"
    memory="$(grep 'Peak memory:' "$runtime/generation.log" | sed -E 's/.*: ([0-9.]+) GB.*/\1/' | tail -1)"
  fi
  printf "%-14s %s/%s      %-8ss %-10s %-10s %sGB\n" "$profile" "$passed" "$total" "$seconds" "$prompt" "$generation" "$memory"
}

bos_eval_compare() {
  local first="${1:-}" second="${2:-}" yes=0
  shift $(( $# >= 2 ? 2 : $# ))
  [[ "${1:-}" == "--yes" ]] && yes=1
  bos_profile_exists "$first" || { bos_die "Unknown profile: $first"; return 1; }
  bos_profile_exists "$second" || { bos_die "Unknown profile: $second"; return 1; }
  bos_profile_supported "$first" || { bos_die "$first: $(bos_profile_value "$first" unsupported_reason)"; return 1; }
  bos_profile_supported "$second" || { bos_die "$second: $(bos_profile_value "$second" unsupported_reason)"; return 1; }
  local previous="$(bos_active_profile)"
  if [[ "$yes" -eq 0 ]]; then
    bos_warn "Evaluation will temporarily stop the active model and may take a long time."
    print -n "Compare $first and $second? [y/N]: "
    local answer; read -r answer
    [[ "${answer:l}" == "y" ]] || return 0
  fi
  source "$BOS_ROOT/lib/bos/lifecycle.zsh"
  local profile result=0
  for profile in "$first" "$second"; do
    bos_stop || true
    bos_start --model "$profile" || { result=1; break; }
    "$BOS_ROOT/benchmark/run.sh" "$profile" || result=1
    "$BOS_ROOT/benchmark/measure-model.sh" "$profile" || result=1
    bos_stop || true
    [[ "$result" -eq 0 ]] || break
  done
  bos_stop || true
  [[ -n "$previous" ]] && bos_start --model "$previous" || true
  printf "\n%-14s %-9s %-9s %-10s %-10s %s\n" PROFILE PASS WALL PROMPT_TPS GEN_TPS MEMORY
  bos_eval_summary "$first"
  bos_eval_summary "$second"
  bos_info "BOS does not change the selected default automatically."
  return "$result"
}

bos_eval() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    compare) bos_eval_compare "$@" ;;
    *) bos_die "Usage: bos eval compare <profile> <profile> [--yes]"; return 1 ;;
  esac
}
