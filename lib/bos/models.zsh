#!/bin/zsh

bos_models() {
  bos_ensure_dirs
  local selected="$(bos_selected_model)" active="$(bos_active_profile)"
  local profile cache expected model runtime cached availability cache_path
  printf "%-14s %-9s %-9s %-8s %-10s %-7s %s\n" PROFILE SELECTED ACTIVE RUNTIME STATUS MEMORY MODEL
  jq -r '.profiles | keys[]' "$BOS_MODELS" |
    while IFS= read -r profile; do
      cache="$(bos_profile_value "$profile" cache)"
      expected="$(bos_profile_value "$profile" expected_memory_gb)"
      model="$(bos_profile_value "$profile" model)"
      runtime="$(bos_profile_value "$profile" runtime)"
      cached="no"
      availability=""
      cache_path="$HOME/.cache/huggingface/hub/$cache"
      [[ -d "$cache_path" && -z "$(find "$cache_path" -name '*.incomplete' -print -quit 2>/dev/null)" ]] && cached="yes"
      availability="$([[ "$(bos_profile_value "$profile" supported)" == "false" ]] && echo unavailable || echo "$cached")"
      printf "%-14s %-9s %-9s %-8s %-10s %-7s %s\n" "$profile" "$([[ "$profile" == "$selected" ]] && echo yes || echo no)" "$([[ "$profile" == "$active" ]] && echo yes || echo no)" "$runtime" "$availability" "${expected}GB" "$model"
    done
}

bos_model() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
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
    *) bos_die "Usage: bos model select <profile>"; return 1 ;;
  esac
}
