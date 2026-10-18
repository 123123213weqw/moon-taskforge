# Changelog

## 1.1.0 — 2026-10-18

Registry version: 0.10.0.

同步保留公开版已有的 Merkle 指纹、目标闭包、提前截断、日志、取消和执行证据，新增 impact：对 changed_inputs 计算直接输入消费者及依赖传播闭包，逐项说明触发文件和受影响依赖，保留未影响任务列表。此操作不执行命令，拒绝不安全路径；同时拒绝重复或大小写冲突的输入声明。

## Unreleased

- `scripts/bench.py` validates scale against independent closures (1000-task chain and fan-in plans, closure-exact invalidation after one input change, a 120-command executor run) and records timings in docs/benchmarks.md; the scale check runs in CI. reference.py gained a main guard so its helpers can be imported.
- `--status [WORKSPACE]` (and `status` from the module) summarizes the journal of the last run: what needed work and why, waves with durations, failures with log paths, pruned files and whether the run was interrupted.
- Every attempt's complete output is written to `.taskforge/logs/<id>-<digest>.<attempt>.log` (disable with `options.logs: false`); the journal keeps its bounded 64 KiB tail and records the log path.
- Tasks accept `grace_ms` (0-60000): on timeout the executor sends SIGTERM and escalates to SIGKILL after the grace period, so processes can clean up; a timed-out task still fails.
- The cache is persisted before every wave, so a cancelled or interrupted run keeps its finished work and a rerun only repeats the wave that was in flight; `execute` accepts `options.signal` (an `AbortSignal`) for programmatic cancellation.
- `propagate: "content"` enables early cutoff: dependencies only order execution and invalidation follows declared file digests, so a producer that reproduces identical outputs leaves its dependents cached. The default `fingerprint` mode is unchanged.
- `targets` (request field, workflow field or repeated `--target` flag) limits a run to the named tasks and their transitive dependencies; other tasks are reported `skipped` and never scheduled.
- Requests may carry `executables` (program name to digest); when a task's program has a digest it is part of the fingerprint, so a changed tool invalidates the task. Fingerprints of hosts that do not supply digests are unchanged.
- The executor hashes each task's program when the workflow sets `hash_executables: true` (explicit path or `PATH` lookup) and records the digests in the journal.
- The executor passes only SHA-256 digests of environment values to the planner, so the cache and journal never contain raw environment values; invalidation on a changed value is unaffected.
- `node scripts/execute.mjs --plan WORKFLOW [WORKSPACE]` hashes and plans without executing or writing anything; `--why TASK` explains a task: status, reason, changed fingerprint fields versus the cache entry, output digests current versus recorded, dependency statuses. Both are also exported as `plan` and `why` from the module.
- The cache file now accumulates entries across runs and workflows sharing a workspace instead of being replaced; a task that failed drops its entry.
- `--prune` deletes files the cache records as outputs that no current task declares and drops cache entries of removed tasks; `pruned` lists them in the result and journal.
- Results and journals report `duration_ms` for the run and `{tasks, duration_ms}` per wave.
- Fingerprints are now Merkle nodes (fingerprint version 2): SHA-256 digests of each field, dependencies' node digests, and the node's own digest. Reports and caches stay constant-size per task — a 200-task chain's report shrinks from 194 MB to 278 KB and plans in 0.09 s instead of 0.93 s. SHA-256 is implemented in the package and exposed as `digest(String)`; version 1 caches are rebuilt once.
- Stress fixtures (deep chain, wide fan-in, limits, unicode ids, self-dependency) and oracle checks for structured 200-task chains and 150-way fan-ins, with every fingerprint node verified against an independent Python computation.

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
