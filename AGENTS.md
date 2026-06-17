# Agent Notes

Builder OS (`bos`) is a local-first workstation control plane:

```text
bos -> OpenCode coding agent -> local model runtime
```

## Read First

- Product/user docs: `README.md`
- Workstation operations and runtime details: `WORKSTATION.md`
- Contribution, tests, and releases: `CONTRIBUTING.md`
- Model profiles: `config/models.json`
- Project templates: `templates/`

## Working Method

- Keep changes small, explicit, and local-first.
- Prefer existing Zsh helpers in `lib/bos/` over new abstractions.
- Preserve macOS, DGX Spark, and generic Linux behavior separately.
- Do not commit secrets, model weights, generated dependencies, or local state.
- Add focused tests for behavior changes.

## Useful Commands

```sh
./install.sh
./tests/run.zsh
zsh -n bin/bos lib/bos/*.zsh tests/*.zsh
git diff --check
```

## Runtime Notes

- macOS uses MLX-LM.
- DGX Spark is `linux-spark` and uses Ollama by default.
- Generic Linux uses a dedicated vLLM environment or `BOS_VLLM_BIN`.
- Model downloads are explicit: use `bos model fetch`; `bos start` should not
  hide large downloads.
- Optional local secrets and machine overrides live in `.env`; keep real values
  out of git.

## Release Rule

When asked to prepare a tag or release, update the shipped version first:

- `bin/bos`
- README release badge
- `CHANGELOG.md`

Tags must match the CLI version exactly, for example `v0.1.2` for `bos 0.1.2`.
Do not suggest or create a tag until those files are in sync.
