# Builder OS Roadmap

Builder OS is a local-first agentic development control plane for macOS and
Linux workstations. Its command-line interface is `bos`.

It does not replace the operating system, model runtime, OpenCode, Git, or
project frameworks. It provides one stable operator interface above them so
those components remain observable, replaceable, and under explicit control.

## Product Principles

- **One command surface:** daily operations begin with `bos`.
- **Local-first:** inference, project memory, metrics, and evaluation stay local
  unless explicitly configured otherwise.
- **Operator control:** every background process, model, permission, and memory
  record is inspectable and removable.
- **Delegate, do not duplicate:** use OpenCode for the interactive coding loop,
  MLX-LM or vLLM for inference, Git for source history, and native user services
  for process management.
- **Measured evolution:** models and agent policies earn promotion through
  repeatable evaluations.
- **Portable projects:** generated projects are normal independent repositories,
  not applications trapped inside BOS.

## Target Command Surface

### Lifecycle

```sh
bos start                         # Start the default model in the background
bos start --model coder-next      # Start a selected model profile
bos stop                          # Gracefully stop the active model
bos restart                       # Restart the active/default model
bos status                        # Show model, PID, uptime, endpoint, and health
bos logs                          # Follow model-server logs
```

`bos start` should return control to the terminal after the model becomes ready.
Model lifecycle should use a managed background service rather than requiring a
dedicated terminal window.

### Projects And Agent Sessions

```sh
bos init my-app                   # Create ./my-app using the default web template
bos init my-api --type api        # Create another registered project type
bos open my-app                   # Open the project in OpenCode
bos open .                        # Open the current repository in OpenCode
bos sessions --project my-app    # List saved project conversations
bos sessions --projects          # Group saved sessions by project
bos session resume --project my-app
bos do --project my-app "fix the tests"
bos job list --project my-app     # Inspect asynchronous execution attempts
bos job attach JOB-ID             # Open the real OpenCode session for a job
bos projects                      # List registered/local projects
bos project register .            # Register an existing project
bos project show my-app           # Show project metadata and memory status
```

For the first version, `web` is the default project type. Templates must remain
ordinary directories/scripts with explicit versions and no hidden framework
magic.

BOS should expose normal session lifecycle operations itself. Direct
`opencode ...` invocation is an advanced passthrough for capabilities that do
not yet have a BOS-native contract, not the expected user workflow.
Interactive session resume should provide a terminal picker, while explicit
session IDs, `--latest`, list output, and JSON remain available for automation.

### Asynchronous Agent Jobs

```sh
bos do --project my-app "Build the settings page"
bos job list --project my-app
bos job show JOB-ID
bos job logs JOB-ID
bos job diff JOB-ID
bos job attach JOB-ID
bos job message JOB-ID "Address the review feedback"
bos job stop JOB-ID
bos job approve JOB-ID
bos job deny JOB-ID
```

`bos do` is the ergonomic entry point for delegating work without opening the
OpenCode TUI. BOS should create an execution job, create or reuse an OpenCode
session through a persistent local OpenCode backend, send the prompt
asynchronously, record identifiers and events, then return control immediately.

`bos job attach` should open the actual OpenCode TUI attached to the existing
session. Exiting or detaching from the TUI must not stop the job. `bos job stop`
must abort the OpenCode session deliberately; killing or restarting BOS itself
must not lose durable job/session linkage.

Like work commands, `bos do` is project-scoped. It may infer the project when
run inside a registered project; elsewhere it requires
`--project <name|path|.>`. `bos job message` should continue the same OpenCode
session with operator follow-up rather than creating an unrelated execution.

Jobs should expose explicit states:

- `queued`: accepted by BOS but not yet started.
- `running`: OpenCode is actively executing the task.
- `waiting-for-approval`: OpenCode requested a gated action.
- `blocked`: the agent cannot make progress without operator input.
- `failed`: execution ended unsuccessfully.
- `completed`: execution and required verification finished.
- `cancelled`: deliberately aborted by the operator.

Async execution must preserve the same strict-local policy and permissions as
interactive sessions. BOS must never auto-approve gated operations merely
because a job is detached. Approval requests should pause the job, appear in
`bos job show`, `bos cc agents`, and `bos cc review`, and be resolved through
explicit approve, deny, or attach actions.

### Machine And Model Observability

```sh
bos top                           # Live dashboard, refreshed until quit
bos status --watch                # Compact watch mode
bos metrics                       # One-shot machine and model metrics
bos models                        # List configured, cached, and active models
bos model show default            # Show profile, cache size, limits, and benchmark
```

The live dashboard should include:

- Active model profile, PID, uptime, health, and server port.
- Unified-memory usage, memory pressure, swap, and available headroom.
- Model-process CPU and memory usage.
- Disk usage for model caches and benchmark results.
- Recent OpenCode session/tool statistics.
- Optional generation throughput from recent benchmark or server logs.

### Evaluation And Selection

```sh
bos eval default                  # Run behavior and runtime evaluation
bos eval compare default coder-next
bos model select default          # Set the default after explicit selection
bos doctor                        # Validate installation and configuration
bos setup                         # Guided initial installation/configuration
```

Model selection must remain explicit. Evaluation can recommend a winner, but it
must not silently replace the default.

### Memory

```sh
bos memory status
bos memory inspect my-app
bos memory search "authentication decision"
bos memory rebuild my-app
bos memory forget my-app
```

Memory must be inspectable source material, not an opaque agent database.

### Local Capability Services And Data Jobs

```sh
bos services
bos service show ocr
bos service start ocr
bos service status ocr
bos service eval ocr
bos data run --project archive ingest-documents
bos data schedule --project archive ingest-documents --cron "0 2 * * *"
bos data jobs --project archive
```

BOS should manage reusable local capabilities such as OCR, document parsing,
web search, crawling, transcription, embeddings, and media conversion. Each
capability should expose a stable localhost API usable by project backends and
durable data jobs. OpenCode should receive a smaller project-scoped tool or MCP
adapter over that same API rather than becoming the capability's owner.

OCR is the first proposed proving ground. PaddleOCR is the leading initial
candidate because it includes lightweight multilingual OCR, layout-aware
document parsing, structured Markdown/JSON output, service deployment, and
benchmark support. It must still earn selection against simpler or independent
challengers through a representative local evaluation corpus.

See [CAPABILITY-SERVICES.md](CAPABILITY-SERVICES.md) for the proposed service
contract, OCR candidate study, data provenance rules, and delivery order.

### Command Center And Work

```sh
bos cc                             # Open the Builder OS Command Center
bos cc my-app                      # Open one project's overview
bos cc plan my-app                 # Open one project's planning view
bos cc kanban [my-app]             # Open a project or global Kanban view
bos cc agents                      # Watch active agent work across projects
bos cc review                      # Open the operator review queue
bos cc jobs [my-app]               # Inspect asynchronous execution attempts
bos work list --project my-app     # List one project's work
bos work list --all                # Deliberately list work across projects
bos work add --project my-app "Build billing settings"
bos work show --project my-app WORK-ID
bos work move --project my-app WORK-ID review
bos work run --project my-app WORK-ID
```

The **Builder OS Command Center** is the future local UI for understanding and
directing the workstation. It should combine project status, planned work,
active agent sessions, machine/model health, recent outcomes, and verification
evidence without replacing OpenCode's coding interface.

The Command Center should support multiple useful views over the same data:

- A workstation overview showing registered projects, Git state, health,
  recent activity, blocked work, and active agents.
- A project view showing architecture/memory, milestones, work items, sessions,
  checks, and recent changes.
- A planning view connecting product direction, milestones, dependencies,
  backlog, and current execution priorities.
- A Kanban view for moving work through backlog, planned, active, blocked,
  review, and done.
- An agent activity view showing which project and work item each session is
  handling, its current phase, elapsed time, model, latest tool activity, and
  whether operator input is required.
- A jobs view showing queued, running, waiting, failed, completed, and
  cancelled execution attempts with attach/stop actions.
- A review queue showing proposed changes, test evidence, memory updates, and
  decisions awaiting approval.

`bos cc` should bind only to localhost and read from BOS's normal registries,
work records, memory, Git, OpenCode sessions, and runtime metrics. The UI is a
projection over inspectable local data, never a second hidden source of truth.

`cc` means **Command Center**. Running `bos cc` opens the default workstation
overview; its subcommands are shortcuts into named views. `bos ui` may remain a
discoverable alias, but `bos cc ui` should not exist because it adds no meaning.
Keep `bos work` as the scriptable data-operation namespace beneath the visual
Command Center.

Work commands are project-scoped. Inside a registered project, BOS may infer
the current project, allowing commands such as `bos work list` and
`bos work add "Fix onboarding"`. Outside one, commands must use
`--project <name|path|.>`. Cross-project operations must be explicit through
`--all`; BOS should never silently combine unrelated project work.

### BOS Guide

```sh
bos guide                          # Start a local management-assistant chat
bos guide --project my-app         # Discuss and manage one project
bos cc guide                       # Open Guide inside the Command Center
```

The **BOS Guide** is a lightweight local management-assistant layer for people
who should not need to understand terminals, Git, models, OpenCode, or BOS
command syntax. A user should be able to say:

> I want a simple website where customers can request appointments. Help me
> decide what to build first and keep me updated.

Guide should translate that intent into understandable project choices,
proposed plans, milestones, work items, jobs, reviews, and status explanations.
It should speak in product and outcome language, ask focused questions, explain
tradeoffs, and hide implementation machinery unless the user asks for it.

Guide is not a coding agent and must not reimplement OpenCode. Its role is to:

- Understand high-level goals and turn them into proposed BOS operations.
- Explain project/job health, progress, failures, approvals, and next decisions.
- Create or revise plans and work items after showing proposed changes.
- Delegate approved implementation jobs to OpenCode through BOS.
- Summarize outcomes and verification evidence in non-technical language.
- Escalate uncertain product decisions and gated actions to the human.

Every meaningful Guide action must compile into typed, inspectable BOS
operations such as registering a project, creating work, moving a work item,
starting a job, or approving a specific request. The chat transcript is not the
source of truth, and natural-language interpretation must never bypass normal
BOS permissions, previews, confirmations, or audit history.

Guide should eventually be available both inside the Command Center and through
a simple local desktop application. The desktop experience should prioritize
chat, project cards, current progress, decisions requiring attention, and clear
approve/deny controls. Advanced technical details remain available but are not
required for ordinary use.

Guide should use a separate lightweight local model profile so it remains
responsive while the coding model and development tools are active. Do not
hardcode a model family before evaluation. Benchmark candidates such as compact
Gemma, Qwen, or other small instruction/tool-calling models for:

- Reliable typed BOS action generation and argument selection.
- Following approval boundaries and refusing ambiguous destructive actions.
- Product planning, clarification quality, and non-technical explanations.
- Low memory use, low latency, and coexistence with the active coding model.

The Guide model may propose actions but BOS validates and executes them. A
larger coding model or OpenCode session should be used when implementation,
repository reasoning, or deep technical diagnosis is required.

Guide inference should be independently managed from the coding-model service.
BOS may keep a sufficiently small Guide model warm when resources permit, or
load it on demand and unload it after inactivity. Its lifecycle, memory budget,
latency, and fallback behavior must remain visible in `bos status` and the
Command Center.

## Responsibility Boundaries

### BOS Owns

- Global `bos` CLI and stable command contracts.
- Background model lifecycle and health checks.
- Model profile registry and selected default.
- Project registry, templates, and initialization.
- Inspectable work-item format, state transitions, and orchestration metadata.
- Async job lifecycle, OpenCode session linkage, event capture, and approvals.
- Typed management actions, Guide policy, and human-readable status summaries.
- Machine/model observability and logs.
- Durable project/workstation memory policy and indexes.
- Evaluation orchestration, score history, and promotion decisions.
- Setup, diagnostics, upgrades, and configuration migrations.

### OpenCode Owns

- Interactive coding TUI.
- Coding sessions and conversation history.
- Tool invocation and permission enforcement.
- Repository inspection, edits, tests, and diff review.
- Session/token/tool statistics.

OpenCode sessions are useful operational history, but they are not sufficient
as durable memory. Sessions contain transient reasoning and conversation noise;
BOS memory should contain curated facts, decisions, conventions, and outcomes.

BOS should use OpenCode's supported programmatic surfaces rather than
reimplementing its agent loop: non-interactive runs for simple foreground
automation, the headless server/API for durable asynchronous jobs, session
continuation for follow-up work, and TUI attach for live operator intervention.

### Guide Model Owns

- Interpreting conversational goals and asking focused clarification questions.
- Proposing typed BOS operations and explaining their likely consequences.
- Summarizing BOS state, evidence, and decisions in non-technical language.

The Guide model has no direct shell, filesystem, Git, OpenCode, or network
authority. It can only propose operations from an allowlisted schema; BOS
validates permissions, scope, state, arguments, and confirmation requirements
before execution.

### Model Runtimes Own

- Loading local models.
- Prompt processing and generation.
- OpenAI-compatible local inference endpoint.

### Git And Projects Own

- Source history and project-specific documentation.
- Tests, build commands, framework configuration, and application state.
- Project-local work definitions and acceptance criteria when committed to Git.

## Proposed Architecture

```text
bos CLI
├── lifecycle manager
│   ├── launchd-managed MLX-LM service
│   └── systemd-managed vLLM service
├── project registry and templates
├── work registry and orchestration
├── capability-service registry and data jobs
├── observability and logs
├── memory service
├── evaluation runner
├── local Command Center UI
└── adapters
    ├── OpenCode
    ├── runtimes: MLX-LM and vLLM
    ├── capabilities: OCR, search, and future local services
    ├── Git
    └── platforms: macOS and Linux
```

### Repository Layout

```text
.
├── bin/bos                       # Global CLI entrypoint
├── lib/                          # Command implementations and adapters
├── config/
│   ├── models.json               # Model profiles and selected default
│   └── projects.json             # Local project registry, ignored by Git
├── templates/
│   └── web/                      # Default project template
├── memory/                       # Schema, indexing, and policy
├── benchmark/                    # Existing evaluation harness
├── opencode.json
└── .opencode/
```

The first implementation should remain a small, testable shell CLI using `jq`
and native platform tools. Move to a compiled or Python CLI only when shell complexity
becomes a demonstrated maintenance problem.

## Memory Design

Memory should be layered rather than treated as one large vector database.

### Layer 1: Source Of Truth

Human-readable files committed inside each project:

- `README.md`
- `AGENTS.md` or equivalent project instructions
- `docs/architecture.md`
- `docs/decisions/` for architectural decision records
- Tests and source code

This layer has the highest authority.

### Layer 2: Curated BOS Memory

Local structured records derived from completed work:

- Project purpose and architecture summary.
- Commands that successfully build, test, lint, and deploy.
- Decisions, constraints, conventions, and recurring failure resolutions.
- Links back to source files, commits, sessions, and benchmark evidence.

Every record should include provenance, creation time, last verification time,
scope, and a confidence/status field. Records must be reviewable and deletable.

### Layer 3: Retrieval Index

A rebuildable local search index over Layer 1 and Layer 2. Begin with SQLite
full-text search. Add local embeddings only after text retrieval is measured and
shown to be insufficient.

### Layer 4: OpenCode Session History

Use OpenCode's existing session database for recent conversational context,
debugging, and statistics. Do not treat it as permanent truth.

## Work Item Design

BOS needs a small, durable format for work before it needs sophisticated
orchestration. A work item should be understandable and editable without BOS or
an LLM.

The initial source format should be ordinary Markdown with structured
frontmatter, stored project-locally under `.bos/work/` when it belongs in Git,
or in BOS local data for private/workstation-only items. Each item should
include:

- Stable ID, project, title, objective, and status.
- Acceptance criteria and verification commands.
- Dependencies, priority, labels, and optional milestone.
- Assigned agent/session and current execution phase.
- Created, started, updated, reviewed, and completed timestamps.
- Outcome summary, evidence, relevant files, commits, and memory proposals.

Allowed statuses should begin small and explicit: `backlog`, `planned`,
`active`, `blocked`, `review`, and `done`. Kanban columns, timelines, project
progress, and agent queues are derived views over these records.

Agents may propose transitions and updates, but BOS records them and preserves
an event history. Starting work should create or attach an OpenCode session;
finishing work should require recorded verification evidence before moving to
`done`. The operator must be able to edit, move, archive, or delete every item.

## Job And Session Design

Keep three related concepts separate:

- A **work item** describes the desired outcome, acceptance criteria, and
  durable planning state.
- A **job** is one execution attempt against a work item or direct `bos do`
  request.
- An **OpenCode session** is the underlying agent conversation used by that job.

One work item may have multiple jobs due to retries, changed models, failed
verification, or operator-directed follow-up. Every job should record its
project, optional work-item ID, OpenCode session ID, model/profile, prompt,
status, timestamps, process/backend identity, event/log locations, approvals,
diff evidence, verification outcome, and final result.

BOS should manage a local headless OpenCode backend as a service adapter, send
prompts asynchronously, monitor its event stream, and reconcile state after BOS
or terminal restarts. OpenCode remains responsible for reasoning, tools,
permissions, edits, tests, diffs, and conversation history. BOS owns durable
job state, orchestration, visibility, notifications, and operator actions.

The first implementation should support one active job per project to avoid
concurrent edits in the same working tree. Later parallel execution must use
explicit isolated Git worktrees rather than allowing multiple agents to edit
the same checkout.

## Delivery Phases

### Phase 0: Workstation Baseline - Complete

- OpenCode configured exclusively for local MLX inference.
- Qwen3.6 selected through repeatable evaluation.
- Agent planning, autonomy, permissions, and strict-local policy configured.
- Benchmark and operational documentation established.

### Phase 1: Global BOS CLI - Complete

- Add `bin/bos` with `help`, `start`, `stop`, `restart`, `status`, `logs`,
  `open`, `models`, and `doctor`.
- Replace direct script usage with internal BOS adapters and remove the legacy
  launch/open scripts after integration validation.
- Store PID, active profile, logs, and runtime state outside Git.
- Install a global command through a symlink in a user-owned PATH directory.
- Add shell completion after command contracts stabilize.

**Acceptance:** from any directory, `bos start`, `bos status`, `bos open .`, and
`bos stop` work without entering this repository.

### Phase 2: Managed Background Service And Observability - Complete

- Run MLX-LM through per-user `launchd` and vLLM through `systemd --user`.
- Add readiness timeout, graceful shutdown, stale-PID recovery, and log
  rotation.
- Implement `bos metrics`, `bos status --watch`, and `bos top`.
- Use native memory metrics, `ps`, port-owner tools, available accelerator
  metrics, cache sizes, and OpenCode stats; avoid privileged metrics in the
  default dashboard.

**Acceptance:** the server survives terminal closure, never starts duplicate
instances, and all owned processes/resources are visible from `bos status`.

### Phase 3: Project Registry And Templates - Complete

- Implement `bos init`, `bos open`, `bos projects`, `bos project register`, and
  `bos project show`.
- Register projects by canonical absolute path, defaulting creation to
  `<current-directory>/<project-name>`.
- Create a versioned `web` template with Git initialization, standard docs,
  basic checks, and project-local agent instructions.
- Make framework selection explicit later; do not prematurely hard-code a large
  scaffolding matrix.

**Acceptance:** `bos init my-app` creates a normal independent Git repository and
`bos open my-app` launches OpenCode with workstation policy.

### Phase 4: Durable Memory

- Define a transparent SQLite schema for projects, facts, decisions, commands,
  outcomes, provenance, and verification state.
- Implement inspect/search/rebuild/forget commands.
- Add a post-task proposal flow where agents suggest memory updates but BOS
  validates and records them.
- Start with full-text search; evaluate embeddings separately.

**Acceptance:** project memory can be inspected without an LLM, rebuilt from
source, and completely removed by the operator.

### Phase 5: Evaluation And Model Registry - In Progress

- Move model profile duplication into one registry consumed by lifecycle,
  OpenCode configuration generation, metrics, and benchmarks.
- Add comparable evaluation history and machine-readable scorecards.
- Measure correctness, autonomy, regressions, wall time, prompt speed,
  generation speed, and memory pressure.
- Implement recommendation rules and explicit `bos model select`.

**Acceptance:** adding and comparing a model requires one registry change and a
single `bos eval compare` command.

### Phase 6: Setup, Distribution, And Extensibility - In Progress

- Maintain the idempotent installer and `bos doctor` for fresh-machine setup.
- Maintain platform adapters for macOS and Linux without leaking
  service-manager or metric assumptions into BOS core.
- Maintain runtime adapters for MLX-LM and vLLM; investigate llama.cpp as the
  portable fallback only when evaluation justifies it.
- Add configuration migrations and version reporting.
- Maintain the published MIT license, contribution/security guides,
  architecture decisions, and reproducible setup.
- Add adapter interfaces only when introducing a second runtime or coding agent.
- Consider MCP integration for exposing BOS memory and metrics to OpenCode while
  keeping BOS as the source of truth.

**Acceptance:** another supported macOS or Linux user can clone, run setup,
choose a local model, initialize a project, and use BOS without editing source
files.

### Phase 7: Work Registry And Command Center

- Define and version the inspectable BOS work-item schema and event history.
- Implement project-scoped `bos work list/add/show/move/run/archive` before
  building the UI, with explicit `--project` and `--all` resolution rules.
- Implement `bos do` and `bos job list/show/logs/diff/attach/message/stop` over
  a persistent local OpenCode backend before adding broad scheduling.
- Reconcile job state after restarts and surface pending OpenCode permission
  requests through explicit `bos job approve/deny` actions.
- Link work items to registered projects, Git state, OpenCode sessions,
  verification commands, outcomes, and curated memory proposals.
- Add an agent activity adapter that reports session state without pretending
  to know more than OpenCode exposes.
- Build the local **Builder OS Command Center**, launched through `bos cc`, with
  workstation, project, planning, Kanban, job, agent activity, and review-queue
  views, addressable through focused `bos cc <view> [PROJECT]` commands.
- Keep the server localhost-only, require no cloud account, and make every UI
  mutation equivalent to an inspectable CLI/data operation.
- Add notifications for blocked work, failed verification, completed items, and
  actions requiring operator approval.

**Acceptance:** `bos cc` presents an accurate live view of projects, work, and
agent activity; an item created or moved in either the CLI or UI appears in the
other; and all state remains readable, editable, exportable, and removable
without the UI. `bos do` can start detached work, `bos job attach` can enter its
live OpenCode session without interrupting it, and BOS can safely stop, recover,
and report jobs without recreating OpenCode's agent logic.

### Phase 8: BOS Guide And Desktop Experience

- Define a versioned typed-action schema covering safe Guide interactions with
  projects, plans, work items, jobs, reviews, memory, and status.
- Implement a local `bos guide` chat that turns conversation into previewed BOS
  operations and non-technical explanations.
- Add confirmation tiers so informational/read actions can proceed directly,
  ordinary reversible mutations require a visible preview, and gated actions
  always require explicit approval.
- Create Guide evaluations for intent interpretation, clarification,
  hallucinated identifiers, project scoping, permission boundaries, action
  validity, explanation quality, latency, and memory use.
- Evaluate compact local models rather than selecting one by reputation; ship a
  lightweight Guide profile that can coexist with the coding model.
- Add an independently observable on-demand/warm Guide-model lifecycle with an
  inactivity unload policy and explicit memory budget.
- Integrate Guide into `bos cc guide`, then package the same local Command
  Center/Guide experience as an approachable desktop application.
- Add onboarding that helps a non-technical user describe an idea, create or
  register a project, review the proposed first plan, and delegate the first
  approved job without using a terminal.
- Preserve a complete audit trail connecting each chat-approved action to the
  resulting BOS operation, work item, job, OpenCode session, and outcome.

**Acceptance:** a non-technical user can describe a project goal, understand and
approve a proposed plan, delegate implementation, monitor progress, answer
clarifying questions, review outcomes, and stop work through chat without
learning BOS commands; every action remains inspectable and enforceable outside
the chat or desktop application.

### Phase 9: Local Capability Services And Data Workflows

- Define a versioned capability registry and common health, task, result,
  artifact, provenance, permission, resource-budget, and evaluation schemas.
- Evaluate PaddleOCR text/document profiles against Tesseract and docTR using
  real intended documents on macOS and Linux.
- Implement `bos service list/show/start/stop/status/logs/eval` without coupling
  capability lifecycle to the active coding model.
- Expose a stable localhost OCR/document API for project backends.
- Add a narrow project-scoped OpenCode/MCP adapter over the BOS-owned API.
- Implement durable `bos data run/jobs/show/logs/cancel/retry` workflows with
  idempotency, checkpoints, artifacts, validation, and provenance.
- Add scheduling only after one-time jobs are reliable and inspectable.
- Apply the proven contract to explicitly enabled web search, crawling, and
  other local capabilities.
- Show services, resource conflicts, data jobs, quality warnings, and derived
  datasets in Command Center.

**Acceptance:** a project backend and an authorized OpenCode session can use the
same local OCR capability; a large document-ingestion job can be stopped,
resumed, inspected, and reproduced; every derived record retains provenance and
the capability implementation can be replaced without changing project data
contracts.

## Near-Term Decisions

- Product name: **Builder OS**.
- Primary command: **`bos`**.
- Optional human-friendly alias: `boss`, only after `bos` is stable.
- Runtime manager: per-user `launchd` on macOS and `systemd --user` on Linux.
- Initial CLI implementation: shell plus `jq`.
- Default project type: `web`.
- Default coding agent: OpenCode.
- Default inference runtime: MLX-LM on Apple Silicon and vLLM on Linux.
- Initial memory retrieval: SQLite full-text search, not embeddings.
- Default model promotion: explicit operator action after evaluation.
- Local UI name: **Builder OS Command Center**, launched with `bos cc`.
- Command Center views: `bos cc plan`, `bos cc kanban`, `bos cc agents`,
  `bos cc jobs`, and `bos cc review`; keep `bos ui` only as an optional
  discoverability alias.
- Initial work states: backlog, planned, active, blocked, review, and done.
- Work-item source format: inspectable Markdown plus structured frontmatter.
- Async execution command: `bos do`; execution lifecycle namespace: `bos job`.
- Initial concurrency policy: one active job per project checkout.
- Management assistant name: **BOS Guide**, available through `bos guide` and
  `bos cc guide`.
- Guide authority: typed allowlisted BOS actions only; no direct tool access.
- Guide model selection: compact local candidates must pass dedicated
  management/action-safety evaluations before becoming the default.
- Capability architecture: stable localhost APIs are the source of truth; MCP
  adapters expose narrow agent tools but do not own lifecycle or durable state.
- First capability study: OCR/document parsing, with PaddleOCR as the leading
  candidate pending representative evaluation.
- Data-workflow policy: one-time durable jobs before scheduling; every derived
  record retains provenance, validation state, and service/profile version.

## Non-Goals

- Replacing the host operating system or implementing kernel-level scheduling.
- Reimplementing OpenCode's coding TUI or tool system.
- Building a multi-agent swarm before one-agent workflows are reliable.
- Allowing concurrent agents to edit the same project checkout.
- Turning the Command Center into an opaque autonomous project manager.
- Letting conversational convenience bypass BOS permissions or confirmations.
- Using the Guide model as a substitute for OpenCode's coding agent.
- Automatically granting broad machine access to agents.
- Treating raw conversations or generated summaries as unquestionable memory.
- Supporting operating systems beyond Apple Silicon macOS and systemd-based
  Linux in the first versions.
