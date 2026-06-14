# Local Agent Evaluation

The benchmark compares configured model profiles through the same OpenCode and
MLX stack used by Builder OS.

The public interface is:

```sh
bos eval compare default coder-next
```

BOS temporarily starts each profile, runs the agent behavior suite, stops the
service for standalone runtime measurement, restores the previously active
profile, and prints a comparison. It never changes the selected default.

The behavior suite copies each scenario into an isolated temporary Git
repository and measures whether the agent can inspect, plan, edit, test, and
self-correct. It covers:

- Bug fixing.
- Repository explanation.
- Failing-test diagnosis.
- Feature implementation.

Generated event logs, diffs, test output, and runtime measurements are written
under `benchmark/results/` and ignored by Git. The internal adapter scripts
remain directly callable for development, but model metadata comes from the
shared `config/models.json` registry.
