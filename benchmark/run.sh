#!/bin/zsh

set -euo pipefail

BASE_DIR="${0:A:h:h}"
export BOS_ROOT="$BASE_DIR"
source "$BASE_DIR/lib/bos/common.zsh"
BENCHMARK_DIR="$BASE_DIR/benchmark"
PROFILE="${1:-default}"
OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$BENCHMARK_DIR/results/$STAMP-$PROFILE"

MODEL="$(bos_profile_value "$PROFILE" opencode_model)"
if [[ -z "$MODEL" ]]; then
  echo "Unknown model profile: $PROFILE"
  exit 1
fi

if [[ ! -x "$OPENCODE_BIN" ]]; then
  echo "OpenCode not found at $OPENCODE_BIN"
  exit 1
fi

if ! curl --silent --fail --max-time 2 http://127.0.0.1:8080/v1/models >/dev/null; then
  echo "Start the requested model first: bos start --model $PROFILE"
  exit 1
fi

mkdir -p "$RESULT_DIR"
print "scenario\tseconds\ttests" > "$RESULT_DIR/summary.tsv"

export OPENCODE_CONFIG="$BASE_DIR/opencode.json"
export OPENCODE_DISABLE_AUTOUPDATE=1
export OPENCODE_DISABLE_SHARE=1
export HTTP_PROXY="http://127.0.0.1:9"
export HTTPS_PROXY="http://127.0.0.1:9"
export ALL_PROXY="http://127.0.0.1:9"
export NO_PROXY="localhost,127.0.0.1"

for scenario in "$BENCHMARK_DIR"/scenarios/*; do
  name="${scenario:t}"
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/local-agent-$name.XXXXXX")"
  cp -R "$scenario/fixture/." "$workdir/"
  git -C "$workdir" init -q
  git -C "$workdir" add .
  git -C "$workdir" -c user.name=benchmark -c user.email=benchmark@local commit -qm baseline

  start="$(date +%s)"
  "$OPENCODE_BIN" run \
    --pure \
    --format json \
    --model "$MODEL" \
    --agent workstation \
    --dir "$workdir" \
    "$(cat "$scenario/task.md")" \
    > "$RESULT_DIR/$name.events.jsonl" \
    2> "$RESULT_DIR/$name.stderr.log" || true
  elapsed="$(($(date +%s) - start))"

  if (cd "$workdir" && zsh "$scenario/test.sh") \
      > "$RESULT_DIR/$name.tests.log" 2>&1; then
    test_status="pass"
  else
    test_status="fail"
  fi

  git -C "$workdir" diff --stat > "$RESULT_DIR/$name.diffstat.txt"
  git -C "$workdir" diff > "$RESULT_DIR/$name.diff.patch"
  print "$name\t$elapsed\t$test_status" >> "$RESULT_DIR/summary.tsv"
done

echo "Benchmark complete: $RESULT_DIR"
column -t -s $'\t' "$RESULT_DIR/summary.tsv"
