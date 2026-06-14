# Bake-off Results

Benchmark date: 2026-06-12

Hardware: MacBook Pro, Apple M5 Max, 64 GB unified memory

Runtime: MLX-LM 0.31.3, OpenCode 1.17.4

## Decision

Keep `mlx-community/Qwen3.6-35B-A3B-4bit` as the default workstation model.
Both finalists passed all four agent scenarios, but Coder Next took almost four
times as long and used more than twice the peak model memory. It does not meet
the requirement to remain within twice the default model's wall-clock time.

## Agent Scenarios

| Scenario | Qwen3.6 | Coder Next |
| --- | ---: | ---: |
| Bug fix | 41s, pass | 96s, pass |
| Repository explanation | 34s, pass | 134s, pass |
| Failing-test diagnosis | 28s, pass | 171s, pass |
| Feature implementation | 33s, pass | 140s, pass |
| **Total** | **136s, 4/4** | **541s, 4/4** |

## Standalone Runtime

| Measurement | Qwen3.6 | Coder Next |
| --- | ---: | ---: |
| Prompt processing | 151.843 tok/s | 11.025 tok/s |
| Generation | 131.946 tok/s | 93.786 tok/s |
| MLX peak memory | 19.682 GB | 44.991 GB |
| 512-token command wall time | 6.89s | 15.33s |

Detailed event logs, diffs, and test outputs are retained under
`benchmark/results/`.
