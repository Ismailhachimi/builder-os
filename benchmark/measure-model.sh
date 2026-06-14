#!/bin/zsh

set -euo pipefail

BASE_DIR="${0:A:h:h}"
export BOS_ROOT="$BASE_DIR"
source "$BASE_DIR/lib/bos/common.zsh"
PROFILE="${1:-default}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$BASE_DIR/benchmark/results/$STAMP-$PROFILE-runtime"

MODEL="$(bos_profile_value "$PROFILE" model)"
if [[ -z "$MODEL" ]]; then
  echo "Unknown model profile: $PROFILE"
  exit 1
fi

mkdir -p "$RESULT_DIR"
bos_health || { echo "Start the requested model first: bos start --model $PROFILE"; exit 1; }

pid="$(bos_model_pid)"
rss_kb="$([[ -n "$pid" ]] && ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ' || echo 0)"
start="$(date +%s)"
curl --silent --fail "$BOS_ENDPOINT/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model "$MODEL" '{model:$model,messages:[{role:"user",content:"Inspect a Python repository, identify a failing test, plan the fix, and explain which tools you would call."}],max_tokens:512}')" \
  > "$RESULT_DIR/response.json"
elapsed="$(($(date +%s) - start))"
prompt_tokens="$(jq -r '.usage.prompt_tokens // 0' "$RESULT_DIR/response.json")"
generation_tokens="$(jq -r '.usage.completion_tokens // 0' "$RESULT_DIR/response.json")"
generation_tps="$(awk -v tokens="$generation_tokens" -v seconds="$elapsed" 'BEGIN {if(seconds<1) seconds=1; printf "%.3f", tokens/seconds}')"
peak_gb="$(awk -v kb="${rss_kb:-0}" 'BEGIN {printf "%.3f", kb/1024/1024}')"
{
  echo "Prompt: $prompt_tokens tokens, unavailable tokens-per-sec"
  echo "Generation: $generation_tokens tokens, $generation_tps tokens-per-sec"
  echo "Peak memory: $peak_gb GB"
  echo "Wall time: $elapsed seconds"
} > "$RESULT_DIR/generation.log"

echo "Runtime measurement complete: $RESULT_DIR"
cat "$RESULT_DIR/generation.log"
