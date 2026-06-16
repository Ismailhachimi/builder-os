# Builder OS

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release: v0.1.0](https://img.shields.io/badge/release-v0.1.0-4c8bf5.svg)](CHANGELOG.md)

Builder OS (`bos`) gives macOS and Linux workstations one command for local
agentic development:

```text
bos -> OpenCode coding agent -> local model runtime
```

It runs the model locally, opens coding sessions in any project, creates
full-stack projects, monitors memory, and compares local models.

## Quick Start

### 1. Requirements

- Apple Silicon macOS with MLX-LM, or Linux with systemd and a working vLLM
  installation.
- Internet access during installation and the first model download.
- At least 25 GB free disk space for the default model.
- 32 GB or more unified memory on macOS. Linux memory requirements depend on
  the selected model; roughly 64 GB or more is recommended for the default.

On a fresh Mac, install Apple's command-line tools first:

```sh
xcode-select --install
```

### 2. Install

```sh
git clone https://github.com/IsmailHachimi/builder-os.git
cd builder-os
./install.sh
```

The installer automatically installs or configures:

- Homebrew/Python 3.11/`jq` on macOS, or basic system packages on Linux.
- OpenCode.
- The global `bos` command.
- The isolated MLX-LM environment on macOS.
- OpenCode's runtime-neutral local provider adapter.

It does not download a model until you start one.

On Linux, BOS creates a dedicated vLLM Python environment at
`~/venvs/vllm` when vLLM is not already available. BOS does not install or
replace accelerator drivers or CUDA. Set `BOS_VLLM_BIN` when using a custom
vLLM executable.

### Linux Setup

1. Make sure the machine's accelerator drivers and CUDA stack are working.
2. Clone Builder OS and run `./install.sh`.
3. Run `bos doctor`, then `bos start`.

When the local runtime exposes vLLM through a wrapper or a non-default path,
export `BOS_VLLM_BIN=/absolute/path/to/wrapper` before installing and using BOS.
The wrapper must accept normal `vllm serve ...` arguments. The installer records
that absolute path in `~/.config/bos/config.json`. If no custom path is set,
the installer creates and uses `~/venvs/vllm/bin/vllm`.

### 3. Start Building

Open a new terminal after installation:

```sh
bos start
```

The first start downloads the recommended model, approximately 20 GB. After the
download, inference and normal starts are local.

Open the current repository in the coding agent:

```sh
cd /path/to/your/project
bos open .
```

Or create a new full-stack project:

```sh
bos init my-app
bos open my-app
```

That is the complete normal setup.

## Update

From the cloned Builder OS repository:

```sh
git pull
./install.sh
```

The installer is safe to rerun. It preserves user configuration, synchronizes
the service environment, and refreshes the global `bos` symlink.

## Everyday Commands

```sh
bos start                    # Start the selected model in the background
bos stop                     # Stop it
bos restart                  # Restart it
bos status                   # Show model health and memory
bos top                      # Live dashboard with CPU/memory graphs
bos top --once               # Print one dashboard snapshot
bos top --interval 2         # Use a slower custom refresh interval
bos logs                     # Follow model logs

bos open .                   # Open the current repository in OpenCode
bos open my-app              # Open a registered project
bos sessions --project my-app
bos session resume --project my-app
bos projects                 # List registered projects
bos project register .       # Register an existing project
bos init my-app              # Create a new project interactively

bos models                   # Show available and active models
bos model select default     # Select the model used by the next start
bos eval compare default coder-next
bos doctor                   # Check the installation
```

The model service survives terminal closure but does not automatically start at
login.

## New Projects

`bos init my-app` defaults to `./my-app` in the current directory and asks you
to confirm or change the destination. It then asks about the product, visual
direction, database, authentication, and future infrastructure target before
creating and installing an independent Git repository using the default web
stack:

- pnpm and Turbo.
- Next.js, Tailwind, and shadcn-compatible configuration.
- NestJS with validation, security defaults, and JWT skeleton.
- Shared Zod contracts.
- PostgreSQL and Drizzle ORM by default, with Prisma available as an alternative.

Node.js and pnpm are installed automatically the first time they are needed.

Accept every default without questions:

```sh
bos init my-app --yes
bos init my-app --path ~/Projects/my-app
bos init my-app --orm prisma --yes
```

When PostgreSQL is selected interactively, BOS asks whether to use Drizzle or
Prisma. Drizzle is the default.

Register an existing project without opening an agent session:

```sh
cd ~/Projects/existing-app
bos project register .

bos project register ~/Projects/existing-app --name my-app
```

OpenCode conversations remain saved after leaving the TUI. Manage them through
BOS:

```sh
bos sessions --project my-app          # List one project's saved sessions
bos session list --project my-app      # Equivalent explicit form
bos sessions --projects                # Group sessions by registered project
bos sessions --all                     # Deliberately list every saved session
bos session resume --project my-app    # Select with arrow keys, then resume
bos sessions --project my-app --select # Select a session and print its ID
bos session resume --project my-app --latest
bos session resume SESSION_ID --project my-app
bos session delete SESSION_ID
```

The interactive picker supports Up/Down or `j`/`k`, Enter to select, and `q` to
cancel. Explicit IDs, `--latest`, regular list output, and `--json` remain
available for scripts and agentic BOS usage.

`bos opencode ...` is an advanced passthrough for OpenCode commands that BOS
does not yet expose directly. Normal workflows should use BOS commands.

## Models

Builder OS ships with two profile names whose runtime/model resolves for the
current platform:

| Profile | macOS / MLX | Linux / vLLM |
| --- | --- | --- |
| `default` | Qwen3.6 35B A3B 4-bit | Qwen3 Coder 30B A3B |
| `coder-next` | Qwen3 Coder Next 4-bit | Upstream BF16 profile is listed but intentionally unavailable |

Only one model runs at a time.

The upstream Linux Coder Next weights need roughly 160 GB before practical
serving overhead, so BOS marks that profile unavailable by default. Add and
evaluate a known-good quantized variant on hardware with sufficient headroom
before enabling it; BOS will not pretend an unsafe profile fits.

```sh
bos model select coder-next
bos restart
```

Selecting a model never interrupts the active service. Restart explicitly when
you want to switch.

## Privacy And Ownership

- Model inference runs locally through MLX-LM on macOS or vLLM on Linux.
- OpenCode web tools and cloud providers are disabled by the shipped policy.
- Projects remain normal independent Git repositories.
- BOS configuration is inspectable JSON under `~/.config/bos/`.
- Runtime state and logs live under `~/Library/Application Support/BuilderOS/`
  on macOS and `~/.local/state/builder-os/` on Linux.
- Model weights live under `~/.cache/huggingface/hub/`.

## More

- [WORKSTATION.md](WORKSTATION.md): operations and customization.
- [CAPABILITY-SERVICES.md](CAPABILITY-SERVICES.md): proposed OCR, local service,
  and data-job architecture.
- [ROADMAP.md](ROADMAP.md): planned memory and platform work.
- [benchmark/RESULTS.md](benchmark/RESULTS.md): model comparison evidence.
- [CHANGELOG.md](CHANGELOG.md): release history.
- [CONTRIBUTING.md](CONTRIBUTING.md): development and contribution guide.
- [SECURITY.md](SECURITY.md): private vulnerability reporting.
- [THIRD_PARTY.md](THIRD_PARTY.md): external software and model licensing.

When something is unclear, begin with:

```sh
bos doctor
bos status
bos logs --lines 100 --no-follow
```

## Open Source And Acknowledgements

Builder OS is an independent project by
[@IsmailHachimi](https://github.com/IsmailHachimi). It integrates with
[OpenCode](https://github.com/anomalyco/opencode) and
[MLX-LM](https://github.com/ml-explore/mlx-lm), and
[vLLM](https://github.com/vllm-project/vllm) as external tools; their source
code is not bundled into this repository. Builder OS is not affiliated with or
endorsed by those projects.

Builder OS is released under the [MIT License](LICENSE). External tools,
models, and generated-project dependencies retain their own licenses; see
[THIRD_PARTY.md](THIRD_PARTY.md).
