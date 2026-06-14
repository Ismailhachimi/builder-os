# Local Capability Services

## Status

This document is a design proposal. No capability-service commands or OCR
runtime are implemented yet.

Builder OS should eventually manage reusable local capabilities such as OCR,
document parsing, web search, crawling, embeddings, transcription, and media
conversion. These capabilities should be usable by:

- Normal project backends through a stable localhost API.
- One-time and scheduled BOS data jobs.
- OpenCode sessions through explicit project-scoped tools or MCP adapters.
- The future Builder OS Command Center and Guide.

The capability service is the reusable primitive. OpenCode integration and job
orchestration are clients of that primitive, not the primitive itself.

## Proposed Shape

```text
project backend ───────────────┐
BOS data job / scheduler ──────┼──> localhost capability API
OpenCode tool or MCP adapter ──┤          │
Command Center / Guide ────────┘          ├──> structured result
                                         ├──> provenance
                                         ├──> artifacts
                                         └──> metrics
```

Every service should have a versioned profile and an inspectable contract:

- Stable name, implementation, version, license, platform support, and runtime.
- Local endpoint, health check, resource expectations, and lifecycle policy.
- Input/output schema, limits, timeout, and supported synchronous/asynchronous
  modes.
- Artifact and cache locations.
- Project allowlist and agent/tool permissions.
- Evaluation fixtures and benchmark history.

Candidate future commands:

```sh
bos services
bos service show ocr
bos service start ocr
bos service stop ocr
bos service status ocr
bos service logs ocr
bos service eval ocr

bos data run --project archive ingest-documents
bos data schedule --project archive ingest-documents --cron "0 2 * * *"
bos data jobs --project archive
```

These are roadmap contracts, not current CLI commands.

## API Before MCP

The service's versioned localhost HTTP API should be the source of truth.
Projects and jobs need a normal API that does not depend on an agent protocol.

An MCP adapter can then expose a deliberately smaller tool surface to OpenCode,
for example `ocr_extract` or `document_parse`. This lets agents use the service
without giving them unrestricted filesystem or network access. MCP should
translate and authorize calls; it should not own lifecycle, results, or durable
state.

A first common service contract should include:

```text
GET  /health
GET  /v1/capabilities
POST /v1/tasks
GET  /v1/tasks/{id}
POST /v1/tasks/{id}/cancel
GET  /v1/tasks/{id}/artifacts
```

Small requests may complete synchronously. Large PDFs, directories, crawls, and
bulk enrichment should always become durable tasks with progress, cancellation,
retries, and resumable outputs.

## OCR Recommendation

[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) is the strongest first
candidate to evaluate:

- Apache 2.0 licensed.
- Actively developed, multilingual, and supports CPU and NVIDIA deployments.
- Covers fast text OCR, document structure, tables, formulas, charts, and
  Markdown/JSON output through different pipelines.
- Includes service-oriented deployment, HTTP clients, benchmarking support,
  and an MCP server.
- Has lightweight OCR pipelines as well as a larger document-understanding VLM.

It should not be treated as one indivisible OCR mode. BOS should evaluate at
least three PaddleOCR profiles:

| Profile | Intended use | Expected output |
| --- | --- | --- |
| `ocr-text` | Fast text detection and recognition | text, boxes, confidence |
| `ocr-document` | Layout-aware PDF/image parsing | Markdown, JSON, coordinates |
| `ocr-document-vl` | Difficult tables, formulas, charts, or irregular pages | structured document result |

The default should probably be the smallest profile that satisfies the task.
GPU-heavy document parsing should not silently compete with an active coding
model for memory.

PaddleOCR is not the only useful option:

- **[Tesseract](https://github.com/tesseract-ocr/tesseract):** mature Apache 2.0
  CPU fallback for simple text and restricted environments, but weaker on
  complex layouts.
- **[docTR](https://github.com/mindee/doctr):** Apache 2.0, clean PyTorch OCR
  library, and a useful independent benchmark challenger.
- **[Surya](https://github.com/datalab-to/surya):** strong OCR, layout,
  reading-order, and table capabilities, but its model weights have
  commercial-use conditions that require careful review.
- **[Marker](https://github.com/datalab-to/marker):** strong
  PDF-to-Markdown/JSON pipeline, but GPL code and commercial self-hosting terms
  make it a poor default BOS dependency.

The first selection must be earned through a BOS evaluation set containing:

- Clean scans, phone photos, screenshots, and low-quality images.
- Multilingual text relevant to actual projects.
- Multi-column PDFs, tables, forms, formulas, charts, and reading order.
- Accuracy, coordinate quality, structured-output validity, hallucination rate,
  throughput, latency, peak memory, and cold-start time.
- macOS/Apple Silicon behavior and Linux behavior across available accelerators.

## Data Jobs And Provenance

OCR becomes much more valuable when connected to durable data jobs. A project
should be able to define an ingestion pipeline such as:

```text
discover documents
-> fingerprint and deduplicate
-> OCR / parse
-> validate structured output
-> normalize and enrich
-> store records and artifacts
-> record provenance and quality
```

The same job model can later include local or explicitly enabled web search,
crawling, transcription, classification, and embeddings.

Every derived record should retain:

- Source URI or local artifact identity.
- Content hash and parser/service profile version.
- Processing timestamps and job ID.
- Raw result, normalized result, confidence, warnings, and validation outcome.
- License, collection policy, and deletion/retention metadata when applicable.

Jobs must be idempotent and resumable. Scheduling should not imply permission:
network use, external directories, and publication remain explicitly configured
per project and per job.

## Resource And Security Rules

- Bind services to localhost by default.
- Do not expose endpoints to the LAN without an explicit authenticated profile.
- Keep capability-service lifecycle separate from the coding-model lifecycle.
- Use resource budgets and conflict rules so OCR cannot unexpectedly evict or
  starve the active coding model.
- Restrict project and agent access through allowlists and typed operations.
- Treat uploaded documents and OCR output as untrusted data.
- Record service versions and evaluation evidence before promotion.
- Keep service implementations replaceable behind BOS-owned contracts.

## Delivery Recommendation

1. Define the capability registry and common task/result schemas.
2. Build a small evaluation corpus from real intended documents.
3. Compare PaddleOCR text/document profiles against Tesseract and docTR.
4. Implement one localhost OCR service adapter and lifecycle.
5. Add project-scoped API credentials or capability grants.
6. Add a narrow OpenCode/MCP adapter.
7. Add durable one-time data jobs, then scheduling.
8. Generalize the registry to web search and other capabilities only after OCR
   proves the contract.

The important architectural choice is to avoid building an OCR island. OCR is
the first proving ground for a general local capability and data-workflow layer.
