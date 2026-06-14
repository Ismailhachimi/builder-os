#!/bin/zsh

set -euo pipefail

TEST_ROOT="${0:A:h:h}"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/bos-tests.XXXXXX")"
export HOME="$TEST_TMP/home"
export BOS_ROOT="$TEST_ROOT"
export BOS_PLATFORM="${BOS_PLATFORM:-darwin}"
export BOS_CONFIG_HOME="$HOME/.config/bos"
export BOS_DATA_HOME="$HOME/data"
export BOS_MLX_VENV="$BOS_DATA_HOME/venv"
export PATH="$TEST_TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$HOME" "$TEST_TMP/bin"

typeset -gi TESTS=0 FAILURES=0

cleanup() { rm -rf "$TEST_TMP"; }
trap cleanup EXIT

assert_contains() {
  TESTS+=1
  if [[ "$1" != *"$2"* ]]; then
    print -u2 "FAIL: expected output to contain: $2"
    FAILURES+=1
  fi
}

assert_eq() {
  TESTS+=1
  if [[ "$1" != "$2" ]]; then
    print -u2 "FAIL: expected '$2', got '$1'"
    FAILURES+=1
  fi
}

finish_tests() {
  echo "$TESTS assertions, $FAILURES failures"
  [[ "$FAILURES" -eq 0 ]]
}
