#!/bin/zsh
test -s ARCHITECTURE.md
grep -qi "router" ARCHITECTURE.md
grep -qi "service" ARCHITECTURE.md
grep -qi "risk" ARCHITECTURE.md
test -z "$(git diff --name-only)"
