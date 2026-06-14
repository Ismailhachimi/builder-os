# Contributing

Thanks for helping improve Builder OS.

## Development

Builder OS currently targets Apple Silicon macOS and Linux, and is implemented
primarily in Zsh with `jq`.

```sh
git clone https://github.com/IsmailHachimi/builder-os.git
cd builder-os
./install.sh
./tests/run.zsh
```

The installer is safe to rerun. Tests use isolated temporary homes and fake
system commands where possible.

## Guidelines

- Keep BOS local-first and preserve explicit operator control.
- Prefer existing system tools and small inspectable data formats.
- Keep OpenCode responsible for coding-agent execution instead of duplicating
  its agent loop.
- Do not commit secrets, model weights, generated project dependencies, or
  local BOS/OpenCode state.
- Run `./tests/public-release.zsh` before publishing to check tracked content
  for common personal paths, credentials, private keys, and local artifacts.
- Add focused tests for behavior changes.
- Run `./tests/run.zsh`, `zsh -n bin/bos lib/bos/*.zsh tests/*.zsh`, and
  `git diff --check` before submitting changes.

## Reporting Problems

Use GitHub issues for bugs and feature proposals. For security concerns, follow
[SECURITY.md](SECURITY.md).
