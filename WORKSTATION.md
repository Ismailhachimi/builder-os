# Builder OS Operations

## Install And Update

Fresh installation:

```sh
git clone https://github.com/IsmailHachimi/builder-os.git
cd builder-os
./install.sh
```

Update an existing installation:

```sh
git pull
./install.sh
```

The installer is idempotent. It preserves files in `~/.config/bos/` and
refreshes the global command symlink. On macOS it also synchronizes the pinned
MLX service environment from `requirements.txt`; Linux uses the workstation's
validated vLLM environment.

## State And Ownership

| Resource | Location |
| --- | --- |
| Global command | `~/.local/bin/bos` |
| Repository | the cloned Builder OS directory |
| User configuration | `~/.config/bos/` |
| Model runtime and logs | macOS: `~/Library/Application Support/BuilderOS/`; Linux: `~/.local/state/builder-os/` |
| Model weights | `~/.cache/huggingface/hub/` |
| OpenCode binary | `~/.opencode/bin/opencode` |
| OpenCode configuration | `opencode.json` |
| Model profiles | `config/models.json` |
| Template profiles | `config/templates/` and `~/.config/bos/templates/` |

BOS loads a repository-root `.env` file when present. Use it for local machine
secrets such as `HF_TOKEN`; copy `.env.example` to `.env` and keep real values
out of git. The generated model service exports Hugging Face tokens into the
runtime process so background downloads use the same credentials. Linux defaults
to `HF_HUB_DISABLE_XET=1` to prefer standard HTTP model downloads.

The macOS launchd service uses its own environment in Application Support because
macOS background privacy controls prevent launchd from reading environments
inside protected `Documents` directories. `requirements.txt` reproduces that
environment. Linux runs a per-user systemd service. DGX Spark is detected as
`linux-spark` and uses Ollama by default; generic Linux uses a dedicated vLLM
Python environment at `~/venvs/vllm/bin/vllm`, or the path specified by
`BOS_VLLM_BIN`.

On Linux, ensure the machine's accelerator drivers and CUDA stack are working
before running the BOS installer. On DGX Spark, the installer checks or installs
Ollama. On generic Linux, if vLLM is missing, the installer creates
`~/venvs/vllm` and installs vLLM there. `BOS_VLLM_BIN` may point to an executable
wrapper, provided the wrapper accepts the same arguments as the `vllm` CLI.

## Lifecycle

```sh
bos model fetch
bos start
bos status
bos logs
bos top                      # Live dashboard; Ctrl+C exits
bos top --once               # One snapshot for sharing/debugging
bos top --interval 2         # Override the default one-second refresh
bos stop
```

`bos start` generates and loads a per-user launchd service on macOS or
`systemd --user` service on Linux. It refuses to
replace a different active model; use `bos restart --model <profile>` for an
intentional disruptive switch.

The service listens only on `127.0.0.1:8080`. It is terminal-independent and
does not auto-start at login.

## Models

Edit `config/models.json` to add a model profile. Profiles have common token
limits plus platform variants defining runtime, model/OpenCode identifiers,
cache name, expected memory, and runtime arguments.

```sh
bos models
bos model select <profile>
bos model fetch [profile]
bos restart
```

Selection and runtime are deliberately separate. Selecting a model never
interrupts the active service or OpenCode sessions. Fetching is explicit:
`bos start` expects the selected model to already be present and tells the user to
run `bos model fetch` when it is missing.

Profiles may set `supported: false` with an `unsupported_reason` for a specific
platform. BOS lists those profiles but refuses to select or start them. Spark
profiles should prefer validated Ollama models or NVIDIA's Spark-specific vLLM
container path. Generic Linux model profiles should prefer validated quantized
vLLM checkpoints over full upstream BF16 weights unless the profile is explicitly
marked as a large experimental target.

### DGX Spark vLLM Docker

Do not use generic `pip install vllm` as the Spark default. NVIDIA's Spark vLLM
guidance uses `vllm/vllm-openai:nightly-aarch64` or a Spark-specific source build
for NVFP4 support. Ollama NVFP4 tags are currently macOS/MLX-specific, so the
Spark Ollama default uses `qwen3.6:35b`. A future BOS runtime can wrap the
NVIDIA container path for Spark NVFP4.

Reference command shape:

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

## Projects

`bos init` creates an independent Git repository and registers it locally. The
default destination is `<current-directory>/<project-name>`; interactive runs
let you change it before anything is written.
`bos open` resolves a registered name, explicit path, or `.` and delegates the
interactive coding session to OpenCode using the active model.

```sh
bos init product-name
bos init product-name --path ~/Projects/product-name
bos init product-name --orm prisma --yes
bos project register ~/Projects/existing-product
bos projects
bos open product-name
bos sessions --project product-name
bos sessions --projects
bos session resume --project product-name
```

`bos project register .` adds an existing directory to the local registry
without launching OpenCode. Use `--name` for a custom alias and `--type` to
override the automatically detected project type.

Leaving the OpenCode TUI stops that foreground agent process, but its session is
saved. Use `bos sessions` and `bos session resume` rather than invoking OpenCode
session commands directly. `bos opencode ...` remains an advanced passthrough
for capabilities that do not yet have a BOS-native command.

`bos session resume` opens an interactive arrow-key picker in a terminal.
Scripts and agents should use an explicit session ID, `--latest`, or
`bos sessions --json`.

The web template defaults to PostgreSQL with Drizzle ORM. Interactive creation
offers Prisma after selecting PostgreSQL; scripted creation can use
`--orm prisma`.

The built-in web profile is versioned in `config/templates/web.json`. Custom
profiles can extend the web generator:

```json
{
  "name": "my-web",
  "extends": "web",
  "defaults": {
    "database": "mongodb",
    "visual_direction": "Editorial and typography-led"
  }
}
```

Store custom profiles in `~/.config/bos/templates/my-web.json`, then run:

```sh
bos init project --template my-web
```

## Evaluation

```sh
bos eval compare default coder-next
```

Evaluation temporarily runs each profile through the behavior and runtime
benchmarks, restores the previously active model, and prints a comparison.
Results remain under `benchmark/results/`; promotion remains an explicit
`bos model select` action.

## Development

Run the isolated shell suite:

```sh
./tests/run.zsh
```

Reinstall after changing installer/runtime behavior:

```sh
./install.sh
```

Rebuild the macOS MLX service environment when dependencies intentionally change:

```sh
rm -rf "$HOME/Library/Application Support/BuilderOS/venv"
./install.sh
```

## Troubleshooting

```sh
bos doctor
bos status
bos logs --lines 100 --no-follow
```

- If port `8080` is owned by an unmanaged process, BOS refuses to terminate it.
- If a generic Linux model download is interrupted, Hugging Face resumes partial
  files. Spark Ollama models can be resumed with `bos model fetch`.
- If OpenCode is missing, reinstall it from its official installer, then run
  `bos doctor`.
- If a selected model differs from the active model, run `bos restart`.
