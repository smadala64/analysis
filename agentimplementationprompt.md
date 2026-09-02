# Implementation Prompt — Call Analytics & Categorization System

> Copy everything below this line into your coding agent (GitHub Copilot / Claude Code / etc.).
> Fill in the `<<PLACEHOLDERS>>` before running, or let the agent stub them as config.

---

You are implementing a **call analytics categorization system** for a healthcare call center. Build it as a production-quality Python project. Work through the phases in order, and at the end of each phase show me what you built and wait for my confirmation before continuing.

## Context

Call transcripts and call summaries already exist in an Oracle database (written by an existing summarization process — do NOT rebuild that). Your job is to build everything downstream of the summaries:

1. A **discovery pipeline** that clusters historical call summaries to CREATE a taxonomy of categories and subcategories (this is how the taxonomy is born — it does not exist yet).
2. A **categorization service** that classifies each new call against the active taxonomy shortly after its summary is written, automatically (no manual runs).
3. An **Oracle schema** that stores category sets, versions, applicability rules, and per-call category assignments — with full audit history and no duplication of call data.
4. **Reporting views** for dashboards (custom UI now, Power BI/Tableau later).

**Critical compliance constraint:** call text contains PII/PHI. Every LLM and embedding call MUST go through the company-approved AI endpoint configured in `AI_ENDPOINT_URL` — never a public API default. No call text may be logged, printed, or written anywhere outside Oracle. Enforce this in code (a single `ai_client.py` module is the only place HTTP calls to the model are allowed).

## Tech stack

- Python 3.11+, `python-oracledb` (thin mode) for Oracle, `pydantic` + `pydantic-settings` for config, `structlog` for logging (log call IDs, never call text).
- Clustering: `umap-learn` + `hdbscan` (embed → UMAP to ~10 dims → HDBSCAN).
- LLM/embeddings: a thin `ai_client.py` wrapper with `embed(texts) -> vectors` and `complete(prompt, json_schema) -> dict`, pointed at `AI_ENDPOINT_URL` with model names from config. Use structured/JSON output for all classification responses.
- Packaging: `pyproject.toml`, `src/` layout, `pytest` with an in-memory/fake DB layer for unit tests. Provide a `Dockerfile` for the service.
- Config via environment variables (12-factor): `ORACLE_DSN`, `ORACLE_USER`, `ORACLE_PASSWORD` (support Oracle Wallet as an option), `AI_ENDPOINT_URL`, `AI_API_KEY`, `EMBED_MODEL`, `LLM_MODEL`, `POLL_INTERVAL_SECONDS`, `CONFIDENCE_THRESHOLD` (default 0.6), `MIN_CLUSTER_SIZE` (default 40).

## Existing tables (read-only — adapt names to what I give you later)

- `CALL(call_id PK, call_start_ts, queue_id, client_id, plan_id, state_cd, caller_type, genesis_ref)`
- `CALL_TRANSCRIPT(transcript_id PK, call_id FK, transcript_text CLOB)`
- `CALL_SUMMARY(summary_id PK, call_id FK, summary_text CLOB, created_at)`

## Phase 1 — Oracle schema (DDL + migration script)

Create `db/migrations/001_schema.sql` with these tables (Oracle 19c+ syntax, with PKs, FKs, sensible indexes, and comments on every table/column):

- `CATEGORY_SET(set_id, set_code, set_name, owner, description, is_active)` — category sources: `INTERNAL_AI`, `CARESOURCE_PROVIDER`, future clients are rows, not schema changes.
- `CATEGORY_SET_VERSION(version_id, set_id FK, version_no, status DRAFT|ACTIVE|RETIRED, effective_from, effective_to, source_run_id FK, created_by, notes)` — immutable versions; enforce at most one ACTIVE version per set with a function-based unique index.
- `CATEGORY(category_id, version_id FK, parent_category_id FK nullable, category_code, category_name, description, example_text, lineage_category_id nullable, sort_order)` — subcategories are rows whose `parent_category_id` points at a top-level category in the same version; `lineage_category_id` links to the equivalent category in the prior version.
- `CATEGORY_SET_SCOPE(scope_id, set_id FK, scope_type QUEUE|CLIENT|PLAN|CALLER_TYPE|CALL_TYPE|ALL, scope_value, include_flag)` — applicability rules.
- `CALL_CATEGORY_ASSIGNMENT(assignment_id, call_id FK, category_id FK, version_id FK, assigned_by_type AI_MODEL|RULE|HUMAN, model_name, model_version, confidence, is_primary, run_id FK, assigned_at, status ACTIVE|SUPERSEDED|RETRACTED, superseded_by FK nullable)` — unique on `(call_id, category_id, run_id)`; index tuned for `status='ACTIVE'` reporting queries. Assignments are superseded, never deleted.
- `ANALYTICS_RUN(run_id, run_type INCREMENTAL|REFRESH_CLUSTERING|RECLASSIFY|BACKFILL, date_range_from, date_range_to, model_name, model_version, params CLOB json, started_at, finished_at, status, calls_processed, error_count)`.
- `CLUSTER_PROPOSAL(proposal_id, run_id FK, proposed_name, proposed_parent, cluster_size, exemplar_call_ids CLOB json, mapped_category_id FK nullable, review_status PENDING|APPROVED|MERGED|REJECTED, reviewed_by, reviewed_at)`.
- `CALL_PROCESSING_STATUS(call_id PK/FK, stage READY|CATEGORIZED|FAILED|DEAD_LETTER, attempts, last_error, updated_at)`.

Also create `db/migrations/002_seed.sql`: insert the `INTERNAL_AI` set scoped `ALL`, and a `CARESOURCE_PROVIDER` set scoped to queues `<<CARESOURCE_QUEUE_IDS>>`, plus a special reserved category set/row for `UNCLASSIFIED`.

Reserve a special `UNCLASSIFIED` category in every internal version — the classifier assigns it when nothing clears the confidence threshold; these calls feed the next discovery run.

## Phase 2 — Data access layer + AI client

- `src/callcat/db.py`: connection pooling (`oracledb.create_pool`), repository functions (fetch summaries by date range, fetch pending calls `FOR UPDATE SKIP LOCKED`, insert assignments batch, run lifecycle, active-version lookup, scope-rule lookup). All SQL in one module, bind variables everywhere, no string-formatted SQL.
- `src/callcat/ai_client.py`: the ONLY module that talks to the model endpoint. Retries with exponential backoff, timeout, batch embedding support, and a startup assertion that `AI_ENDPOINT_URL` is set and not a known public API host.

## Phase 3 — Discovery pipeline (taxonomy creation via clustering)

`src/callcat/discovery.py`, runnable as `python -m callcat.discover --from 2026-01-01 --to 2026-06-30 [--sample 20000]`:

1. Create an `ANALYTICS_RUN` row (`REFRESH_CLUSTERING`).
2. Pull summaries for the range (sampled if `--sample` given). Use summaries, not transcripts.
3. Embed via `ai_client.embed` in batches; cache embeddings to a local parquet keyed by call_id so re-runs don't re-embed.
4. UMAP to ~10 dims → HDBSCAN (`min_cluster_size` from config). Keep the noise bucket; report its size.
5. For each cluster: select ~10 representative summaries (nearest centroid + 3 random). Call the LLM with **Prompt A** (below) to produce `{name, definition, example}`. These are subcategory candidates.
6. One final LLM call with **Prompt B** over all cluster labels to group them into 10–20 parent categories and merge near-duplicates, returning a two-level JSON taxonomy.
7. Write everything to `CLUSTER_PROPOSAL` (status PENDING) and print a human-readable review report (cluster sizes, names, exemplar snippets — exemplars referenced by call_id, text truncated to one line).
8. Nothing goes live automatically: a separate command `python -m callcat.publish --run <run_id>` takes APPROVED proposals and creates a new `CATEGORY_SET_VERSION` (DRAFT→ACTIVE, retiring the previous version) with `lineage_category_id` mapped where `mapped_category_id` was set.

**Prompt A (cluster labeling)** — system: "You are naming call-reason categories for a healthcare call center. Given example call summaries that belong to one group, return JSON: {name: max 5 words, definition: one sentence, example: one short synthetic example — do not copy real text}. Name the specific reason, not a vague theme."

**Prompt B (hierarchy building)** — system: "Given this list of call-reason subcategories (name + definition + size), organize them into 10–20 parent categories for call-center reporting. Merge duplicates (list which merged). Return JSON: [{parent_name, parent_definition, children:[subcategory names]}]. Every subcategory must appear exactly once."

## Phase 4 — Categorization service (the always-on classifier)

`src/callcat/service.py`, runnable as `python -m callcat.serve`:

1. Poll loop: every `POLL_INTERVAL_SECONDS`, claim up to N calls from `CALL_PROCESSING_STATUS` where stage=`READY` using `FOR UPDATE SKIP LOCKED` (design the claim so multiple replicas are safe). Structure the trigger as a strategy interface so Oracle AQ can replace polling later without touching classification logic.
2. For each call: resolve applicable category sets from `CATEGORY_SET_SCOPE` against the call's queue/client/plan/caller_type.
3. Internal set: call LLM with **Prompt C** — the active version's category tree (codes, names, definitions) + the summary; response JSON `{primary: code, secondary: [codes], confidence: 0-1, rationale: one sentence}`. Below `CONFIDENCE_THRESHOLD` → assign `UNCLASSIFIED`.
4. CareSource set (only when applicable): **Prompt D** — the fixed CareSource label list `<<CARESOURCE_LABELS>>` + summary; multi-label JSON response.
5. Write assignment rows (batch insert) with model name/version, confidence, run_id; mark call `CATEGORIZED`. On error: increment attempts, `FAILED`, and after 3 attempts `DEAD_LETTER`.
6. Also provide `python -m callcat.backfill --from --to` reusing the same classification code path for historical calls.

## Phase 5 — Reporting views

`db/migrations/003_views.sql`:

- `V_CALL_CLASSIFICATION_CURRENT` — active assignments joined to call dimensions (date, client, plan, state, queue, caller_type, set owner, parent category, subcategory, is_primary, confidence). No summary/transcript text.
- `V_CALL_REASON_TREND` — daily counts by category × dimension.
- `V_EMERGING_REASONS` — UNCLASSIFIED counts per week + newest categories per version.
- `V_CARESOURCE_PROVIDER_REPORT` — CareSource-label rollups for their provider inquiry/dispute reporting.

## Phase 6 — Tests & runbook

- Unit tests: scope-rule resolution (CareSource call gets both sets; member call gets internal only), threshold → UNCLASSIFIED path, supersede-not-delete on reclassification, single-ACTIVE-version constraint, dead-letter after 3 failures. Mock `ai_client` — tests must never hit the network.
- Integration test script against a sandbox Oracle (`docker run gvenzl/oracle-free` for local dev) with ~50 synthetic summaries (invent them — plausible but fictional healthcare call reasons).
- `README.md`: setup, env vars, how to run discovery → review → publish → serve → backfill, and the PHI rules for contributors.

## Ground rules

- Never delete or update rows in the existing CALL/TRANSCRIPT/SUMMARY tables.
- Never log, print, or persist summary/transcript text outside Oracle (truncated one-line exemplars in the review report are the only exception).
- All LLM responses must be schema-validated JSON; on parse failure retry once, then treat as classification failure.
- Idempotency: re-running any phase must not duplicate rows (use the unique constraints).
- Ask me before adding any dependency beyond those listed.

Start with Phase 1 and show me the DDL for review.
