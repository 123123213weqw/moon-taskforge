# Moon TaskForge

Incremental local task execution, implemented in MoonBit with a JSON CLI and reusable library API: validate a task graph, plan bounded waves in dependency order, fingerprint inputs and reuse verified outputs, explain every rebuild, block work behind failures, and keep a recovery journal.

- Repository: [https://github.com/123123213weqw/moon-taskforge](https://github.com/123123213weqw/moon-taskforge)
- Package: `123123213weqw/moon_taskforge` on mooncakes.io (registry versions are listed in CHANGELOG.md)
- License: Apache-2.0
- Release scope: **1.0.0 complete implementation** of the scope defined in `docs/proposal.md`. The three proposed scenarios run end to end through the real executor, the acceptance checks (100 reference-validated task graphs, invalidation sets, cache digest verification, failure paths) are executable, and the remaining limits are listed in [docs/boundaries.md](docs/boundaries.md). See [CHANGELOG.md](CHANGELOG.md) for what changed since 0.1.0.

## Implemented

- **Graph validation**: unique non-empty ids, argv commands, relative input/output paths (spaces allowed, no `..`, no absolute or drive paths), case-insensitive and nested output conflicts, unknown or duplicate dependencies, cycles, and produced inputs whose producer is not a (transitive) dependency are all rejected before anything runs.
- **Deterministic planning**: tasks are reported in execution order (every task after its dependencies, ties by id in UTF-16 code unit order); the ready wave is bounded by `concurrency`; `targets` limits a run to the named tasks and their transitive dependencies and reports the rest as `skipped`.
- **Fingerprints and cache**: a task's fingerprint is a Merkle node — SHA-256 digests of its command, declared input digests, declared outputs and explicit environment, the digests of its dependencies' fingerprints, optionally its program's digest, and the node's own digest — so it stays constant-size however deep the graph. A cache entry is reused only when the fingerprint matches *and* every declared output still has the recorded digest; invalidation propagates transitively through dependency digests by default, or follows declared file contents only with `propagate: "content"` (early cutoff: a producer that reproduces identical outputs leaves its dependents cached).
- **Reasons**: every task report carries a `reason` — `fingerprint and outputs verified`, `fingerprint changed: inputs|command|environment|dependencies|outputs`, `outputs missing`, `outputs changed`, `no cache entry`, `no outputs declared`, `missing input: …`, `dependency failed: …`, `waiting for: …`, `concurrency limit reached`, or the executor's report.
- **Summary**: ids grouped by status plus `rerun`, the failed and blocked tasks the next run will attempt, in execution order.
- **Executor** (`scripts/execute.mjs`): hashes declared files with SHA-256, optionally hashes each task's program (`hash_executables: true`, resolved as an explicit path or on `PATH`) so a changed tool invalidates its tasks, passes only digests of environment values to the planner so caches and journals never hold raw values, runs ready waves as child processes (argv, `shell=false`) with per-task timeouts and retries, verifies outputs exist before reporting success, persists the cache atomically after every wave so an interrupted run keeps its finished work, writes a journal with the initial plan (why each task ran), every attempt's exit code, timeout flag, duration and bounded output, and the wave structure; SIGINT/SIGTERM or an `AbortSignal` passed as `options.signal` cancel running children.

## Build and run

Use MoonBit and Node.js 24. The core library supports JS, wasm, wasm-gc and native; the filesystem/process CLI is JS only.

```sh
moon update
moon build --target js
moon run cmd/main --target js -- examples/request.json       # plan a graph from a JSON request
node _build/js/debug/build/cmd/main/main.js examples/request.json
node scripts/execute.mjs examples/codegen/workflow.json WORKSPACE          # execute a workflow for real
node scripts/execute.mjs --plan examples/codegen/workflow.json WORKSPACE   # hash and plan, execute nothing
node scripts/execute.mjs --why test examples/codegen/workflow.json WORKSPACE   # explain one task against the cache
node scripts/execute.mjs --prune examples/codegen/workflow.json WORKSPACE  # also delete outputs no task declares any more
node scripts/execute.mjs --target compile examples/codegen/workflow.json WORKSPACE   # only compile and what it needs
```

Pass `-` to read a UTF-8 JSON request from stdin. A single request must be at most 16 MiB. Successful requests print one JSON result; invalid requests print `{"error": "..."}` and exit nonzero. The executor copies nothing: run it in a scratch copy of a scenario directory (`scripts/scenarios.mjs` does this automatically). `--plan` prints the plan the executor would start from without running or writing anything; `--why TASK` prints the task's status and reason, which fingerprint fields differ from its cache entry, current versus recorded output digests, and its dependencies' statuses. The cache file accumulates entries across workflows that share a workspace; a task that fails drops its entry. `--prune` deletes files the cache records as outputs that no current task declares (and drops entries of removed tasks) before executing; it never touches undeclared files. Results and journals carry the run duration and each wave's tasks and duration.

## Library use

mooncakes.io currently accepts only zero-major versions (`moon publish` rejects anything else with "In this very early stage, the major version must be '0'"), so repository releases and registry versions are numbered separately. The registry version corresponding to each repository release is recorded in [CHANGELOG.md](CHANGELOG.md); `0.1.0` is the initial implementation.

```sh
moon add 123123213weqw/moon_taskforge@REGISTRY_VERSION
```

In the consumer's `moon.pkg`:

```moonbit
import {
  "123123213weqw/moon_taskforge" @engine,
  "moonbitlang/core/json",
}
```

```moonbit
fn example(request : Json) -> Json raise {
  @engine.execute(request)
}
```

`execute(Json) -> Json raise` is the standard JSON boundary. `parse(StringView) -> Value raise`, `from_json(Json) -> Value`, `Value::to_json`, `run(Value) -> Value raise` and `load_tasks(Value) -> Array[Task] raise` (validated tasks in execution order) provide a typed interface; `digest(String) -> String` is the SHA-256 (hex, UTF-8) used for fingerprint fields, so a consumer can recompute them. Object key order in requests is not significant; numeric values are finite doubles. The public interface is listed in `pkg.generated.mbti`.

## Requests and results

A plan request has `tasks` (each `{id, command, deps?, inputs?, outputs?, timeout_ms?, retries?}`) and optionally `hashes` (declared file → digest, as observed by the host), `cache` (the previous result's `cache`), `completed` (`success`/`failed` reports from the executor), `environment` (string map, part of the fingerprint), `executables` (program → digest), `targets`, `propagate` (`fingerprint` or `content`) and `concurrency`. The result has `tasks` (id, status, reason, fingerprint, in execution order), `ready` (the next wave with commands, outputs, timeouts and retries), `terminal`, `success`, `summary` and `cache`. The host drives the loop: hash, plan, execute the ready wave, report, repeat until `terminal`. Every documented case in [docs/usage.md](docs/usage.md) is an executable fixture.

## Scenarios

The three scenarios from the proposal live in `examples/` as real workflows with their tool scripts and inputs; `scripts/scenarios.mjs` copies each into a temporary workspace, runs it through the executor and checks the documented outcomes:

| Scenario | Workflow | What the passes show |
| --- | --- | --- |
| `examples/codegen` | generate a model from a schema → bundle → test | first run executes all three; the second is fully cached with reasons; a schema change rebuilds the whole chain and the regenerated model breaks the test (captured output, `rerun: ["test"]`); fixing the source reruns only compile and test |
| `examples/docs` | render pages → index + link check → package | a broken link fails the check, blocks packaging and leaves no artifact while the index still completes; fixing the page reruns render and everything downstream; the clean run is idempotent |
| `examples/assets` | six thumbnails (one slow, one with a space in its path) → manifest, concurrency 2 | waves never exceed 2; the slow asset times out on both attempts, fails and blocks the manifest; after the fix only that asset and the manifest run; a deleted artifact rebuilds only its producer and the manifest stays cached; a forged cache digest is distrusted and rebuilt |

See [docs/scenarios.md](docs/scenarios.md) for the inputs, decision process and verifiable outputs of each scenario.

## Tests and verification

```sh
moon check --deny-warn --target js      # zero warnings on every backend
moon test --target js                   # 33 tests: 30 fixture cases + property tests
moon test --target wasm
moon test --target wasm-gc
moon test --target native               # requires a C compiler
moon build --target js
node scripts/check.mjs                  # the 30 fixtures through the real CLI
python -B scripts/reference.py          # 100 task graphs vs an independent Python oracle
node scripts/integration.mjs            # real subprocesses: cache, invalidation, failure, timeout, retry, env privacy, tool hashing
node scripts/scenarios.mjs              # the three scenarios, 33 checks
python -B scripts/fixtures.py --check   # generated tests and usage guide match tests/cases.json
python -B scripts/stats.py              # source statistics by category
sh scripts/consume.sh REGISTRY_VERSION  # fresh module consumes the published package
```

`tests/cases.json` is the single source of the 30 fixture cases; `scripts/fixtures.py` generates `fixtures_wbtest.mbt` and `docs/usage.md` from it. The property tests drive generated 60-task graphs to completion and compare invalidation sets with an independently computed dependent closure. The oracle in `scripts/reference.py` drives 100 random graphs through the planner and checks that execution order respects every dependency, that waves respect the concurrency bound, that plans are reproducible, and that the invalidation set after an input change, a command change, a lost artifact or a forged cache entry equals the independently computed closure; it also checks failure blocking and that re-executing a distrusted task with identical output restores the cache for everything else. Fixtures and scenario data are synthetic and are not presented as production adoption evidence. CI runs all of the above on every push; the consumption check runs on demand against a registry version.

## Current boundaries

Commands are argv arrays with `shell=false`. This is a local executor, not a security sandbox: supplied commands have the current user's rights. Cache identity includes declared inputs, the explicit environment and, with `hash_executables`, each task's program; undeclared files, libraries loaded by programs and the inherited environment are not hermetic. Tasks without outputs always execute, and so does anything that depends on them. By default a dependent reruns when its producer's fingerprint changed even if the produced bytes did not; `propagate: "content"` switches to early cutoff, where only declared file contents invalidate. Journals record results and the cache is persisted per wave; an interrupted task itself is re-executed, so side effects should be idempotent. Killing a task targets its direct child process, not every grandchild. Output diagnostics are capped at 64 KiB and can contain whatever commands print; environment values appear only as digests. Concurrent hostile workspace mutation is not isolated. See [docs/boundaries.md](docs/boundaries.md).

See [source and dependency attribution](THIRD_PARTY.md). This release does not establish competition eligibility or organizer acceptance.
