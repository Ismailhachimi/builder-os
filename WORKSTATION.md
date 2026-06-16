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

The macOS launchd service uses its own environment in Application Support because
macOS background privacy controls prevent launchd from reading environments
inside protected `Documents` directories. `requirements.txt` reproduces that
environment. Linux runs a per-user systemd service and uses a dedicated vLLM
Python environment at `~/venvs/vllm/bin/vllm`, or the path specified by
`BOS_VLLM_BIN`.

On Linux, ensure the machine's accelerator drivers and CUDA stack are working
before running the BOS installer. If vLLM is missing, the installer creates
`~/venvs/vllm` and installs vLLM there. `BOS_VLLM_BIN` may point to an
executable wrapper, provided the wrapper accepts the same arguments as the
`vllm` CLI.

## Lifecycle

```sh
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
bos restart
```

Selection and runtime are deliberately separate. Selecting a model never
interrupts the active service or OpenCode sessions.

Profiles may set `supported: false` with an `unsupported_reason` for a specific
platform. BOS lists those profiles but refuses to select or start them. The
shipped Linux Coder Next profile uses this guard because its upstream BF16
weights exceed the practical memory budget of many single-workstation systems.

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
- If a model download is interrupted, Hugging Face resumes partial files.
- If OpenCode is missing, reinstall it from its official installer, then run
  `bos doctor`.
- If a selected model differs from the active model, run `bos restart`.
