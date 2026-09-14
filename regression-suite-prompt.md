# Task: Build a readability regression + model-evaluation suite

You are working in the repository for the **Reading Level API**, a FastAPI
transformation service. Read this whole document before writing code.

---

## 1. Context — what the service does

The service has two responsibilities:

1. Rewrite dental insurance denial letters into simpler language at a
   requested grade level.
2. Calculate the Flesch-Kincaid (FK) reading grade of arbitrary text.

Relevant known facts about the codebase:

- Core Python files: `converter.py` (LLM rewrite pipeline), `scorer.py`
  (readability scoring via the `textstat` library), `main.py` (FastAPI server).
- `converter.py` returns a `ConversionResult` dataclass.
- Azure OpenAI (GPT-4o-mini) is the production backend. `converter_claude.py`
  and `converter_openai.py` are local testing variants — **ignore these for
  this task**; the suite targets the production path only.
- The production target reading level is **grade 5**.
- The pipeline includes a dental jargon substitution table, a denial-type
  classifier (7 categories), few-shot examples, Dale-Chall as a secondary
  signal, and fidelity-triggered retries.

**Before writing anything, inspect the repo** and confirm the real function
signatures, the fields on `ConversionResult`, how the Azure client is
configured (env var names for endpoint, key, API version, deployment), and the
existing pytest configuration. Do not guess — the instructions below describe
intent, and the actual names in the code win.

---

## 2. Why this work exists

Two motivations, one tool:

1. **Change validation.** Today, prompt and code changes get checked against
   one or two phrases. That is not enough. We need to run a large corpus and
   get a handful of summary numbers that tell us "these are still good."
2. **Model migration.** GPT-4o-mini is in the deprecated lifecycle stage — no
   new deployments can be provisioned, and existing ones retire in the spring.
   A replacement model will have to be selected and justified. The same suite
   must be able to run against a candidate model so we can put two metric
   tables side by side.

Model selection itself is **out of scope for this task**. But the harness must
make the model swappable by environment variable so that step is trivial later.

---

## 3. Deliverable

A pytest-based integration suite that:

- Runs the production conversion pipeline over a fixed corpus of letters.
- Reports FK grade **minimum, maximum, average, and standard deviation**, plus
  the **pass rate** (share of rows at or below the requested target grade).
- Is **excluded from the normal test run** — it costs money and needs live
  Azure credentials. It runs only when explicitly asked for.
- Reads the model/deployment from an environment variable so a different model
  can be evaluated without touching code.
- Writes a machine-readable per-run output file so two runs can be compared.

---

## 4. Proposed file layout

```
tests/
  integration/
    __init__.py
    conftest.py                      # gating, env config, corpus fixture
    data/
      regression_corpus.csv          # committed; contains no PII/PHI
    test_readability_regression.py   # the suite
    _report.py                       # stats, console table, run-file writer
runs/                                # gitignored output directory
```

Adapt paths to match the repo's existing conventions if they differ.

---

## 5. The corpus

A regression spreadsheet already exists in the project and will be provided
alongside this prompt.

- Convert it to `tests/integration/data/regression_corpus.csv` and **commit
  it**. It has been confirmed to contain no PII or PHI, so it belongs in the
  repo — everyone running the suite must get identical results.
- Inspect the spreadsheet's columns first and report what you find before
  converting. At minimum it should yield an input letter and a target grade.
  If it also carries prior FK scores or expected outputs, preserve those as
  baseline columns.
- Normalize to a clear schema, something like:
  `id, denial_type, target_grade, input_text, baseline_fk (optional)`
- Strip line breaks / embedded commas safely; verify the row count after
  conversion matches the source.

---

## 6. Implementation requirements

### Gating

The suite must not run during a normal `pytest` invocation.

- Register an `integration` marker in the pytest config.
- Add `-m "not integration"` to the default `addopts`, **or** have `conftest.py`
  skip the whole module unless an env var such as `RUN_INTEGRATION=1` is set.
  Use whichever fits the repo's existing config style; state which you chose.
- Explicit invocation should be a single documented command.

### Model configuration

- Read the deployment/model from an environment variable — reuse the existing
  Azure deployment variable if the code already has one, otherwise add an
  override such as `MODEL_UNDER_TEST` that falls back to the current production
  default.
- If the target model supports a reasoning-effort parameter, expose that as an
  optional env var too, defaulting to unset/minimal. This pipeline does not
  need reasoning capability.
- Never hardcode a deployment name in the test.

### Test structure

- **One test function drives the whole corpus** and asserts on the aggregate
  metrics. Do **not** parametrize one test per row — a single stubborn letter
  must not fail the build, and per-row failures produce unusable noise.
- Run the corpus concurrently where safe (a thread pool with a modest worker
  count), but respect Azure rate limits and make the concurrency configurable.
  Handle throttling with backoff rather than letting a 429 fail the run.
- Call the converter functions **directly** for the regression numbers — this
  isolates the pipeline and avoids HTTP overhead.
- Add **one thin smoke test** that exercises the FastAPI endpoint through a
  test client, to validate the request/response contract. It does not need the
  full corpus — a single letter is enough.

### Metrics and reporting

For each run, compute over all rows:

| Metric | Definition |
|---|---|
| `fk_min` | lowest FK grade produced |
| `fk_max` | highest FK grade produced |
| `fk_avg` | mean FK grade |
| `fk_stddev` | standard deviation of FK grade |
| `pass_rate` | share of rows with FK ≤ that row's target grade |
| `n` | rows evaluated |
| `n_errors` | rows that failed to convert (API error, exception) |

Rows that error out must be counted and reported separately, never silently
dropped or scored as zero.

Output:

- Print a readable summary table to the console at the end of the run.
- Write `runs/<timestamp>_<model>.csv` with one row per corpus item:
  `id, target_grade, fk_grade, passed, input_text, output_text, error`.
- Also write a small `runs/<timestamp>_<model>.json` holding just the summary
  metrics plus the model name and run timestamp — this is what gets diffed
  between two models.

### Assertions

Assert on the aggregate, with thresholds defined as named constants at the top
of the test module so they are easy to tune:

```
MAX_AVG_FK      = 6.0
MAX_STDDEV      = 1.5
MIN_PASS_RATE   = 0.75
MAX_FK          = 9.0
```

Rationale for these starting values: the last evaluation workbook (148 rows)
averaged FK 5.65 with 41 rows over 6.0, i.e. roughly a 72% pass rate. The
threshold is set deliberately just above that so the first run reports the
true current position rather than passing by construction. **Expect the first
run to fail on pass rate.** That is the intended outcome — it establishes the
baseline. Do not adjust the constants to make the first run green; report the
actual numbers.

The failure message must print the full metric summary, not just the assert
that tripped.

---

## 7. Out of scope

Do not build these now, but do not architect in a way that blocks them:

- Dale-Chall scoring in the suite (already exists in `scorer.py`; may be added
  to the report later).
- Fidelity checks (tooth numbers, CDT codes, dollar amounts, dates).
- A `compare` mode that diffs two run JSON files.
- Any model catalog, pricing, or retirement-date research.

---

## 8. Acceptance criteria

- [ ] `pytest` with no arguments runs exactly the tests it ran before — no new
      tests execute, nothing hits Azure.
- [ ] The documented explicit command runs the full corpus against the
      configured model.
- [ ] Corpus CSV is committed and its row count matches the source spreadsheet.
- [ ] Changing the model env var changes which model is used, with no code edit.
- [ ] A run produces both the console summary and the two files under `runs/`.
- [ ] `runs/` is gitignored.
- [ ] Errored rows appear in `n_errors` and in the per-row CSV, and are excluded
      from the FK statistics.
- [ ] README (or the repo's existing docs) gains a short section: how to run the
      suite, which env vars it reads, and how to interpret the metrics.

---

## 9. Report back

When done, state:

1. The columns found in the source spreadsheet and the schema you converted to.
2. The gating mechanism you chose and the exact command to run the suite.
3. The actual metrics from a first baseline run against the current production
   model, and whether the assertions passed or failed.
4. Anything in the existing code you had to work around or that looked wrong.
