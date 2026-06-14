#!/bin/zsh

bos_current_project_path() {
  bos_ensure_dirs
  local current="$(pwd -P)"
  jq -r --arg current "$current" '
    [.projects[].path as $path | select($current == $path or ($current | startswith($path + "/"))) | $path]
    | sort_by(length) | reverse | .[0] // empty
  ' "$BOS_PROJECTS"
}

bos_session_project_path() {
  local target="${1:-}"
  local project_dir=""
  if [[ -n "$target" ]]; then
    source "$BOS_ROOT/lib/bos/projects.zsh"
    project_dir="$(bos_resolve_project "$target")" || { bos_die "Project not found: $target"; return 1; }
  else
    project_dir="$(bos_current_project_path)"
    [[ -n "$project_dir" ]] || { bos_die "No current registered project. Use --project <name|path|.> or --all."; return 1; }
  fi
  print -r -- "$project_dir"
}

bos_opencode_sessions_json() {
  local limit="${1:-50}"
  [[ -x "$BOS_OPENCODE_BIN" ]] || { bos_die "OpenCode not found: $BOS_OPENCODE_BIN"; return 1; }
  bos_project_env
  "$BOS_OPENCODE_BIN" --pure session list --format json -n "$limit"
}

bos_sessions_normalize_json() {
  local sessions="$1" session_id directory canonical output="$1"
  while IFS=$'\t' read -r session_id directory; do
    canonical="$directory"
    [[ -d "$directory" ]] && canonical="$(cd "$directory" && pwd -P)"
    output="$(print -r -- "$output" | jq --arg id "$session_id" --arg directory "$canonical" 'map(if .id == $id then .directory = $directory else . end)')"
  done < <(print -r -- "$sessions" | jq -r '.[] | [.id, .directory] | @tsv')
  print -r -- "$output"
}

bos_sessions_for_scope() {
  local target="$1" all="$2" limit="$3" project_dir="" sessions
  (( all )) || project_dir="$(bos_session_project_path "$target")"
  sessions="$(bos_sessions_normalize_json "$(bos_opencode_sessions_json "$limit")")"
  if (( ! all )); then
    sessions="$(print -r -- "$sessions" | jq --arg directory "$project_dir" '[.[] | select(.directory == $directory)]')"
  fi
  print -r -- "$sessions"
}

bos_sessions_by_project() {
  local sessions="$1" registry groups name project_path type count title directory
  registry="$(jq '.projects' "$BOS_PROJECTS")"
  groups="$(print -r -- "$sessions" | jq --argjson projects "$registry" '
    def project_for($directory):
      first($projects[] | select(.path == $directory)) // null;
    {
      registered: [
        $projects[] as $project
        | {
            name: $project.name,
            path: $project.path,
            type: $project.type,
            sessions: [.[] | select(.directory == $project.path)]
          }
      ],
      unregistered: [
        .[] | select(project_for(.directory) == null)
      ] | group_by(.directory) | map({path: .[0].directory, sessions: .})
    }
  ')"

  print -r -- "$groups" | jq -r '.registered[] | [.name, .path, .type, (.sessions | length)] | @tsv' |
    while IFS=$'\t' read -r name project_path type count; do
      printf "%s (%s) - %s session%s\n" "$name" "$type" "$count" "$([[ "$count" == "1" ]] && echo "" || echo "s")"
      printf "  %s\n" "$project_path"
      print -r -- "$groups" | jq -r --arg project_path "$project_path" '.registered[] | select(.path == $project_path) | .sessions[].title' |
        while IFS= read -r title; do
          printf "  - %s\n" "$title"
        done
      echo
    done

  if [[ "$(print -r -- "$groups" | jq '.unregistered | length')" -gt 0 ]]; then
    echo "Unregistered or moved projects"
    print -r -- "$groups" | jq -r '.unregistered[] | [.path, (.sessions | length)] | @tsv' |
      while IFS=$'\t' read -r directory count; do
        printf "  %s - %s session%s\n" "$directory" "$count" "$([[ "$count" == "1" ]] && echo "" || echo "s")"
        print -r -- "$groups" | jq -r --arg project_path "$directory" '.unregistered[] | select(.path == $project_path) | .sessions[].title' |
          while IFS= read -r title; do
            printf "    - %s\n" "$title"
          done
      done
  fi
}

bos_session_picker() {
  local sessions="$1" selected=1 key sequence tty_fd result="" index tty_state
  local -a ids titles directories
  while IFS=$'\t' read -r session_id title directory; do
    ids+=("$session_id")
    titles+=("$title")
    directories+=("$directory")
  done < <(print -r -- "$sessions" | jq -r '.[] | [.id, .title, .directory] | @tsv')
  (( ${#ids} )) || { bos_die "No saved sessions found."; return 2; }
  [[ -r /dev/tty && -w /dev/tty ]] || { bos_die "Interactive session selection requires a terminal. Use an explicit session ID or --latest."; return 1; }

  exec {tty_fd}<>/dev/tty
  tty_state="$(stty -g < /dev/tty)"
  {
    stty -echo < /dev/tty
    print -u "$tty_fd" -n -- $'\e[?1049h\e[?25l'
    while true; do
      print -u "$tty_fd" -n -- $'\e[H\e[2J'
      print -u "$tty_fd" -r -- "Builder OS - Select a saved session"
      print -u "$tty_fd" -r -- "Up/Down navigate  Enter select  q cancel"
      print -u "$tty_fd" -r -- ""
      for index in {1..${#ids}}; do
        if (( index == selected )); then
          print -u "$tty_fd" -r -- "> ${titles[$index]}"
          print -u "$tty_fd" -r -- "  ${directories[$index]}"
        else
          print -u "$tty_fd" -r -- "  ${titles[$index]}"
        fi
      done
      read -u "$tty_fd" -k 1 key
      case "$key" in
        $'\e')
          sequence=""
          read -u "$tty_fd" -t 0.1 -k 2 sequence 2>/dev/null || true
          case "$sequence" in
            '[A') (( selected > 1 )) && selected=$((selected - 1)) ;;
            '[B') (( selected < ${#ids} )) && selected=$((selected + 1)) ;;
          esac
          ;;
        $'\n'|$'\r') result="${ids[$selected]}"; break ;;
        k|K) (( selected > 1 )) && selected=$((selected - 1)) ;;
        j|J) (( selected < ${#ids} )) && selected=$((selected + 1)) ;;
        q|Q) break ;;
      esac
    done
  } always {
    stty "$tty_state" < /dev/tty
    print -u "$tty_fd" -n -- $'\e[?25h\e[?1049l'
    exec {tty_fd}>&-
  }
  [[ -n "$result" ]] || return 1
  print -r -- "$result"
}

bos_sessions() {
  local target="" all=0 json=0 select=0 projects=0 limit=50 sessions
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) target="${2:-}"; shift 2 ;;
      --all) all=1; shift ;;
      --json) json=1; shift ;;
      --select) select=1; shift ;;
      --projects) projects=1; shift ;;
      --limit) limit="${2:-50}"; shift 2 ;;
      *) bos_die "Unknown sessions option: $1"; return 1 ;;
    esac
  done
  [[ "$limit" == <-> ]] || { bos_die "Session limit must be a positive integer."; return 1; }
  (( all && ${#target} )) && { bos_die "Use either --project or --all, not both."; return 1; }
  (( json && select )) && { bos_die "Use either --json or --select, not both."; return 1; }
  (( projects && (${#target} || all || json || select) )) && { bos_die "--projects cannot be combined with project, all, JSON, or selection options."; return 1; }
  if (( projects )); then
    bos_sessions_by_project "$(bos_sessions_for_scope "" 1 "$limit")"
    return 0
  fi
  sessions="$(bos_sessions_for_scope "$target" "$all" "$limit")"
  if (( select )); then
    bos_session_picker "$sessions"
    return
  fi
  if (( json )); then
    print -r -- "$sessions"
    return 0
  fi

  printf "%-32s %-38s %s\n" ID TITLE DIRECTORY
  print -r -- "$sessions" | jq -r '.[] | [.id, .title, .directory] | @tsv' |
    while IFS=$'\t' read -r session_id title directory; do
      printf "%-32s %-38s %s\n" "$session_id" "$title" "$directory"
    done
}

bos_session_resume() {
  local session_id="" target="" latest=0 all=0
  if [[ $# -gt 0 && "$1" != --* ]]; then
    session_id="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project) target="${2:-}"; shift 2 ;;
      --all) all=1; shift ;;
      --latest) latest=1; shift ;;
      *) bos_die "Unknown session resume option: $1"; return 1 ;;
    esac
  done
  (( all && ${#target} )) && { bos_die "Use either --project or --all, not both."; return 1; }
  (( all && latest )) && { bos_die "--latest requires a project scope."; return 1; }
  local project_dir=""
  (( all )) || project_dir="$(bos_session_project_path "$target")"
  if [[ -z "$session_id" && "$latest" -eq 0 && -t 0 && -t 1 ]]; then
    local picker_result=0
    session_id="$(bos_session_picker "$(bos_sessions_for_scope "$target" "$all" 50)")" || picker_result=$?
    (( picker_result == 2 )) && return 1
    (( picker_result == 1 )) && { bos_info "Cancelled."; return 0; }
  fi
  if [[ -z "$project_dir" && -n "$session_id" ]]; then
    project_dir="$(bos_opencode_sessions_json 100 | jq -r --arg id "$session_id" '.[] | select(.id == $id) | .directory' | head -1)"
    [[ -n "$project_dir" && -d "$project_dir" ]] || { bos_die "Session project directory is unavailable."; return 1; }
  fi
  source "$BOS_ROOT/lib/bos/projects.zsh"
  if [[ -n "$session_id" ]]; then
    bos_open "$project_dir" --session "$session_id"
  else
    bos_open "$project_dir" --continue
  fi
}

bos_session_delete() {
  local session_id="${1:-}" yes=0
  [[ -n "$session_id" && "$session_id" != --* ]] || { bos_die "Usage: bos session delete <session-id> [--yes]"; return 1; }
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) yes=1; shift ;;
      *) bos_die "Unknown session delete option: $1"; return 1 ;;
    esac
  done
  if (( ! yes )); then
    print -n -r -- "Delete OpenCode session $session_id? [y/N]: "
    local answer; read -r answer
    [[ "${answer:l}" == "y" ]] || { bos_info "Cancelled."; return 0; }
  fi
  [[ -x "$BOS_OPENCODE_BIN" ]] || { bos_die "OpenCode not found: $BOS_OPENCODE_BIN"; return 1; }
  bos_project_env
  "$BOS_OPENCODE_BIN" --pure session delete "$session_id"
}

bos_session() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    list) bos_sessions "$@" ;;
    resume) bos_session_resume "$@" ;;
    delete) bos_session_delete "$@" ;;
    *) bos_die "Usage: bos session <list|resume|delete> ..."; return 1 ;;
  esac
}

bos_opencode() {
  [[ -x "$BOS_OPENCODE_BIN" ]] || { bos_die "OpenCode not found: $BOS_OPENCODE_BIN"; return 1; }
  bos_project_env
  exec "$BOS_OPENCODE_BIN" --pure "$@"
}
