# Changelog

All notable Builder OS changes will be documented here.

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
