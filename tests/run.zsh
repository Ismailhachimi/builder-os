#!/bin/zsh

set -euo pipefail
ROOT="${0:A:h:h}"

for test_file in "$ROOT"/tests/*.zsh; do
  [[ "${test_file:t}" == "test-helper.zsh" || "${test_file:t}" == "run.zsh" ]] && continue
  echo "==> ${test_file:t}"
  zsh "$test_file"
done
