# Changelog

All notable Builder OS changes will be documented here.

## 0.2.2 - 2026-06-27

- Fixed macOS Docker Desktop detection by adding Docker Desktop's bundled CLI to
  the BOS runtime path.
- Linked Docker Desktop's bundled Compose plugin when `docker compose` is not
  discoverable from the terminal.
- Made `bos dev` offer to open Docker Desktop and wait for the daemon when it is
  installed but not running.
- Fixed generated Docker Compose apps by installing pnpm dependencies once in a
  dedicated setup service with Docker-managed dependency volumes, avoiding
  host/container `node_modules` conflicts and concurrent install races.

## 0.2.1 - 2026-06-27

- Added `bos project reset` to safely back up and recreate registered projects
  after an explicit `RESET <name>` confirmation.
- Preserved the previous project directory as a timestamped backup and restored
  it when reset scaffolding fails before completion.
- Installed `zsh` and `jq` in the Linux GitHub Actions job before shell and JSON
  validation.

## 0.2.0 - 2026-06-18

- Added Docker and Docker Compose setup to the installer for local app
  infrastructure.
- Generated Docker Compose services for the web app, API, and PostgreSQL or
  MongoDB-backed local services.
- Added `bos dev` commands to start, stop, reset, inspect, and tail generated
  app containers from the project registry.
- Made `bos dev` quiet by default with `--verbose` for attached Docker output.
- Added `dev:docker` scripts to generated projects while keeping host `pnpm dev`
  available for matching Node.js environments.
- Documented the disposable local database workflow.

## 0.1.3 - 2026-06-18

- Fixed installer handling for skipped optional Hugging Face tokens.
- Allowed `.env` creation with an empty `HF_TOKEN` without failing setup.

## 0.1.2 - 2026-06-17

- Added DGX Spark detection with Ollama as the default Spark runtime.
- Made model downloads explicit through `bos model fetch` and the installer
  prompt; `bos start` now requires the selected model to already be present.
- Added Linux Node.js tooling bootstrap for generated web projects.
- Added `.env` loading for local secrets such as `HF_TOKEN`.
- Improved Linux model lifecycle progress, stop behavior, and test coverage.
- Documented NVIDIA's Spark vLLM Docker path as an advanced runtime option.

## 0.1.0 - 2026-06-14

Initial public release.

- Added the global `bos` control plane for local model and OpenCode workflows.
- Added MLX-LM/launchd support on Apple Silicon macOS and vLLM/systemd user
  service support on Linux.
- Added platform-specific model profiles, optional accelerator monitoring, and
  dual-OS CI lifecycle coverage.
- Added managed model lifecycle, logs, status, and live dashboard.
- Added project initialization, registration, discovery, and OpenCode launch.
- Added BOS-native OpenCode session listing, grouping, selection, and resume.
- Added Qwen model profiles and repeatable local-agent evaluation fixtures.
- Added the versioned full-stack web template with Drizzle and Prisma choices.
- Documented the roadmap for durable memory, asynchronous jobs, Command Center,
  BOS Guide, local capability services, OCR evaluation, and durable data jobs.
