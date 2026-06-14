#!/bin/zsh

source "${0:A:h}/test-helper.zsh"
source "$BOS_ROOT/lib/bos/common.zsh"
source "$BOS_ROOT/lib/bos/dashboard.zsh"

assert_eq "$(bos_bar 50 10)" "[#####.....]"
assert_eq "$(bos_bar 4.2 10)" "[..........]"
assert_eq "$(bos_bar 150 10)" "[##########]"
assert_eq "$(bos_bar 0 10)" "[..........]"
assert_contains "$(bos_sparkline '0 25 50 75 100' 5)" "."
assert_eq "${#$(bos_sparkline '0 25 50 75 100' 8)}" "8"

finish_tests
