# Builder OS

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release: v0.2.0](https://img.shields.io/badge/release-v0.2.0-4c8bf5.svg)](CHANGELOG.md)

Builder OS (`bos`) gives macOS and Linux workstations one command for local
agentic development:

```text
bos -> OpenCode coding agent -> local model runtime
```

It runs the model locally, opens coding sessions in any project, creates
full-stack projects, monitors memory, and compares local models.

## Quick Start

### 1. Requirements

- Apple Silicon macOS with MLX-LM, NVIDIA DGX Spark with Ollama, or generic
  Linux with systemd and a working vLLM installation.
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
- Docker and Docker Compose for generated app infrastructure.
- OpenCode.
- The global `bos` command.
- The isolated MLX-LM environment on macOS.
- Ollama on DGX Spark.
- OpenCode's runtime-neutral local provider adapter.

It does not hide model downloads behind `bos start`; fetch the model explicitly
with `bos model fetch`, or accept the installer's interactive download prompt.

On DGX Spark, BOS uses Ollama by default and does not create a vLLM Python
environment. On other Linux machines, BOS creates a dedicated vLLM Python
environment at `~/venvs/vllm` when vLLM is not already available. BOS does not
install or replace accelerator drivers or CUDA. Set `BOS_VLLM_BIN` when using a
custom vLLM executable.

Optional local secrets and machine overrides live in `.env` at the repository
root. Copy `.env.example` to `.env` and set `HF_TOKEN` there for more reliable
Hugging Face model downloads. The installer asks for this token on first setup
and creates `.env` for you; pressing Enter leaves it blank. `.env` is ignored by
git.

### Linux Setup

1. Make sure the machine's accelerator drivers and CUDA stack are working.
2. Clone Builder OS and run `./install.sh`.
3. Optionally copy `.env.example` to `.env` and set `HF_TOKEN`.
4. Run `bos doctor`, `bos model fetch`, then `bos start`.

DGX Spark is detected as `linux-spark` and uses Ollama models such as
`qwen3.6:35b`. Generic Linux uses vLLM. When the local runtime exposes
vLLM through a wrapper or a non-default path, export
`BOS_VLLM_BIN=/absolute/path/to/wrapper` before installing and using BOS. The
wrapper must accept normal `vllm serve ...` arguments. The installer records that
absolute path in `~/.config/bos/config.json`. If no custom path is set on generic
Linux, the installer creates and uses `~/venvs/vllm/bin/vllm`.

### 3. Start Building

Open a new terminal after installation:

```sh
bos start
```

If the model is not downloaded yet, run:

```sh
bos model fetch
bos start
```

After the download, inference and normal starts are local.

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
bos project reset my-app     # Backup and recreate a project after confirmation
bos init my-app              # Create a new project interactively
bos dev my-app               # Run a generated app through Docker Compose
bos dev my-app stop          # Stop its local containers

bos models                   # Show available and active models
bos model select default     # Select the model used by the next start
bos model fetch              # Pre-download the selected model
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
- Docker Compose runtime for the web app, API, and local database.

Node.js and pnpm are installed automatically for BOS scaffolding when they are
needed. Generated projects include `compose.yaml`, so the full app can run with
the Node version pinned inside Docker:

```sh
bos dev              # Start web, API, and database
bos dev stop         # Stop everything
bos dev reset        # Delete volumes and restart
bos dev --verbose    # Start attached with full Docker output
```

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

Reset a project by preserving a timestamped backup and recreating the BOS
scaffold at the same path:

```sh
bos project reset my-app
bos project reset ~/Projects/my-app --orm prisma
```

The command asks you to type `RESET <name>` before it moves anything. This is
different from `bos dev reset`, which only resets Docker Compose volumes for an
already generated BOS app.

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

| Profile | macOS / MLX | DGX Spark / Ollama | Generic Linux / vLLM |
| --- | --- | --- | --- |
| `default` | Qwen3.6 35B A3B 4-bit | qwen3.6 35B A3B | Qwen3 Coder 30B A3B AWQ |
| `coder-next` | Qwen3 Coder Next 4-bit | Qwen3 Coder Next | Qwen3 Coder Next NVFP4 GB10 |

Only one model runs at a time.

DGX Spark profiles use Ollama by default because Spark's GB10 software stack is
not the same as generic Linux CUDA. Ollama NVFP4 tags are currently macOS/MLX
specific, so Spark's Ollama default avoids the `-nvfp4` tag. Generic Linux
profiles use quantized vLLM checkpoints and should avoid full upstream BF16
weights for normal BOS workflows.

```sh
bos model select coder-next
bos model fetch coder-next
bos restart
```

Selecting a model never interrupts the active service. Restart explicitly when
you want to switch.

### DGX Spark vLLM Docker

The Spark vLLM path is intentionally not the default BOS install path. NVIDIA's
Spark guidance uses Spark-specific vLLM containers or source builds for NVFP4
support, not the generic `pip install vllm` path. Treat it as an advanced runtime
target for a future BOS profile.

The shape of that setup is:

```sh
docker run --rm --gpus all --network host \
  -e HF_TOKEN="$HF_TOKEN" \
  vllm/vllm-openai:nightly-aarch64 \
  --model nvidia/Qwen3.6-35B-A3B-NVFP4 \
  --host 127.0.0.1 \
  --port 8080 \
  --served-model-name nvidia/Qwen3.6-35B-A3B-NVFP4 \
  --kv-cache-dtype fp8 \
  --attention-backend flashinfer \
  --moe-backend marlin
```

Use NVIDIA's current Spark vLLM page and the vLLM Qwen recipe as the source of
truth before turning this into a BOS-managed runtime.

## Privacy And Ownership

- Model inference runs locally through MLX-LM on macOS, Ollama on DGX Spark, or
  vLLM on generic Linux.
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
[MLX-LM](https://github.com/ml-explore/mlx-lm),
[Ollama](https://ollama.com/), and
[vLLM](https://github.com/vllm-project/vllm) as external tools; their source
code is not bundled into this repository. Builder OS is not affiliated with or
endorsed by those projects.

Builder OS is released under the [MIT License](LICENSE). External tools,
models, and generated-project dependencies retain their own licenses; see
[THIRD_PARTY.md](THIRD_PARTY.md).
