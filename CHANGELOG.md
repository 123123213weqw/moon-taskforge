# Changelog

## Unreleased

- Requests may carry `executables` (program name to digest); when a task's program has a digest it is part of the fingerprint, so a changed tool invalidates the task. Fingerprints of hosts that do not supply digests are unchanged.
- The executor hashes each task's program when the workflow sets `hash_executables: true` (explicit path or `PATH` lookup) and records the digests in the journal.
- The executor passes only SHA-256 digests of environment values to the planner, so the cache and journal never contain raw environment values; invalidation on a changed value is unaffected.

## 1.0.0 — 2026-10-16

Registry version: not yet published. mooncakes.io requires `0.x.y` version numbers, so this release needs a zero-major registry number; `0.1.0` on the registry is the initial implementation.

Complete implementation of the proposed scope: the three scenarios run end to end through the real executor, the acceptance checks are executable, and the release is verified against independent oracles.

### Planner

- Every task report carries a `reason`: cache hits explain their verification, stale tasks name the first changed fingerprint field or the missing/changed outputs, waiting tasks name what they wait for, blocked tasks name the failed dependency.
- Results include a `summary` (ids grouped by status) with `rerun`, the failed and blocked tasks the next run will attempt, in execution order.
- Deterministic ordering uses UTF-16 code unit order (`String::lexical_compare`) on every backend instead of the toolchain's length-first `Compare for String`.
- `hashes` and `environment` values must be strings; invalid completion statuses, inconsistent success reports, timeouts, retries and concurrency are reported with the offending task or field.
- Error values print their bare message (`task dependency cycle` instead of `InputError(...)`).
- Trait promotions follow the moonbitlang/core policy via `extends.mbt`; the package builds with `--deny-warn` on the 2026-10 toolchain.

### Executor and tooling

- `scripts/execute.mjs` records the initial plan (which tasks needed work and why), per-attempt durations and the wave structure in the journal and in its result.
- `tests/cases.json` grew from 8 to 30 cases (forged cache, lost artifacts, paths with spaces, transitive invalidation, reasons, summary, stricter validation) and is the single source of truth; `scripts/fixtures.py` generates `fixtures_wbtest.mbt` and `docs/usage.md` from it (with `--check` for CI).
- New `scripts/reference.py`: 100 random graphs driven through the planner by an independent Python harness, checking dependency order, bounded waves, reproducibility, invalidation closures after input, command, artifact and cache changes, failure blocking and recovery.
- New `scripts/scenarios.mjs`: the three proposal scenarios through the executor in temporary workspaces, 33 checks.
- New `scripts/stats.py` (source statistics by category) and `scripts/consume.sh` (a fresh module consumes the published package from mooncakes.io).

### Scenarios

- `examples/codegen`, `examples/docs` and `examples/assets` replace the three single-request samples with complete workflows (tool scripts, inputs, timeouts, retries, concurrency bounds), documented in `docs/scenarios.md`; `examples/request.json` is a self-contained planner request for the CLI.

### CI

- `moon check --deny-warn` on all four backends, `moon fmt --check`, interface freshness (`moon info` diff), fixture freshness, the scenarios and the package consumption check on version tags.

## 0.1.0 — 2026-10-05

Initial implementation: graph validation, topological planning, fingerprints, verified cache reuse, transitive invalidation, bounded waves, failure blocking, JSON CLI, Node executor with timeouts, retries and journals, 8 fixture cases, cache oracle, CI on four backends.
