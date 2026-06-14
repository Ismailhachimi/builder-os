#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

tracked="$(git -C "$BOS_ROOT" ls-files)"

TESTS+=1
while IFS= read -r tracked_path; do
  case "$tracked_path" in
    .env.example|*/.env.example) ;;
    .DS_Store|*/.DS_Store|.env|.env.*|*/.env|*/.env.*|benchmark/results/*|projects.json|*/projects.json)
      print -u2 "FAIL: tracked local artifact: $tracked_path"
      FAILURES+=1
      ;;
  esac
done <<< "$tracked"

patterns=(
  '/Users/[^/$"` ]+'
  '/home/[^/$"` ]+'
  'BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY'
  '(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})'
)

for pattern in "${patterns[@]}"; do
  TESTS+=1
  if git -C "$BOS_ROOT" grep -nEI "$pattern" -- . \
      ':!tests/public-release.zsh' >/dev/null 2>&1; then
    print -u2 "FAIL: tracked content matches sensitive pattern: $pattern"
    git -C "$BOS_ROOT" grep -nEI "$pattern" -- . ':!tests/public-release.zsh' >&2 || true
    FAILURES+=1
  fi
done

finish_tests
