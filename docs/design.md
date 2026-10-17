# Implemented architecture (1.0.0)

## Planner

The MoonBit core is a pure planner: given the task graph, the digests of the declared files as the host observed them, the previous cache, the executor's completion reports and the explicit environment, it returns the next bounded wave and a full status report. It never reads files or starts processes.

1. **Validate** (`load_tasks`): ids, argv commands, relative paths, output ownership (case-insensitive, no nesting between owners), dependency references, timeouts (1 ms–24 h), retries (0–10). A dependency cycle is rejected, and so is an input that another task produces unless that producer is a direct or transitive dependency.
2. **Order**: tasks are emitted in execution order — repeated passes over the ids in UTF-16 code unit order, appending every task whose dependencies are already placed. The order is a deterministic topological order.
3. **Fingerprint**: a Merkle node `{version, command, inputs, executable?, outputs, environment, dependencies: {id: digest}, digest}` where `command`, `inputs`, `outputs` and `environment` are SHA-256 digests of the canonical JSON of the respective values, `dependencies` holds the dependencies' node digests, `executable` is the host-supplied program digest when present, and `digest` is the SHA-256 of the canonical node. Including the dependencies' digests is what propagates invalidation transitively (with `propagate: "content"` the field is empty and only declared file digests invalidate, giving early cutoff), and hashing keeps every node constant-size: a 1,000-task chain plans in well under a second with a 1.4 MB report, where embedding full dependency fingerprints produced 194 MB for 200 tasks. SHA-256 is implemented in the package (`sha256.mbt`, FIPS 180-4) so digests are identical on every backend; `scripts/merkle.py` is the independent Python computation the oracle compares against.
4. **Decide** per task, in order: a task outside the `targets` closure is skipped; a failed or blocked dependency blocks it; an executor report of `failed`/`success` is accepted (a `success` without verified inputs/outputs is an input error); otherwise a cache entry with the same fingerprint and matching output digests makes it `cached`; otherwise, with satisfied dependencies, a missing input fails it, and it is `ready` while the wave has room or `waiting` beyond the concurrency bound; with unsatisfied dependencies it is `waiting`.
5. **Explain**: each status carries a `reason`. For stale tasks the planner names the first fingerprint field that differs (`inputs`, `command`, `environment`, `dependencies`, `outputs`), or `outputs missing`/`outputs changed`/`no cache entry`/`no outputs declared`.
6. **Report**: `tasks`, `ready` (commands, outputs, timeout, retries), `terminal`, `success`, `summary` (ids by status and `rerun`), and the refreshed `cache` for every successful or cached task with verified outputs.

## Executor

`scripts/execute.mjs` is the host adapter and the only component with side effects. Per run it validates the whole graph first, digests the explicit environment values and (with `hash_executables`) each task's program, then loops: hash every declared file (SHA-256, regular files only, paths confined to the workspace, no symbolic links), plan, run the ready wave concurrently with `spawn` (argv, `shell=false`, inherited environment plus the explicit map), enforce per-task timeouts with `SIGKILL`, retry as configured, verify outputs exist before reporting `success`, write the journal atomically, and repeat until the plan is terminal. The journal records the initial plan (which tasks needed work and why), executable digests, pruned files, every attempt (exit code, signal, timeout flag, duration, bounded output), each wave's tasks and duration, and the run duration; the cache file is merged and written atomically before every wave (so finished work survives cancellation), keeping entries of other workflows that share the workspace and dropping entries of tasks that failed. `execute` accepts an `AbortSignal` in `options.signal`; aborting terminates the running children and rejects with `Execution cancelled`. `--plan` and `--why` reuse the same preparation without executing; `--prune` removes cache-recorded outputs that no current task declares. `SIGINT`/`SIGTERM` cancel the children. Interrupted runs are re-executed from the cache, not resumed from the journal.

## Determinism

Key order in requests never affects results. Ordering of ids uses `String::lexical_compare` (UTF-16 code units) rather than the toolchain's length-first `Compare for String`. Fingerprints are compared structurally, so digest strings of any form are accepted as long as the host is consistent.

## Public interface

`execute(Json) -> Json raise`, `run(Value) -> Value raise`, `load_tasks(Value) -> Array[Task] raise`, `parse(StringView) -> Value raise`, `digest(String) -> String`, `from_json`, `Value::to_json`, `Value::stringify`, `Value`, `Task`, `InputError`. Trait promotions follow the moonbitlang/core policy (`extends.mbt`). The interface is recorded in `pkg.generated.mbti` and checked in CI.

## Validation evidence

- 30 fixture cases in `tests/cases.json`, run as generated MoonBit white-box tests on JS, wasm, wasm-gc and native, and through the real CLI by `scripts/check.mjs`.
- Property tests in `engine_wbtest.mbt`: generated 60-task graphs driven to completion at concurrency 1, 3 and 8 (order respects every dependency, waves respect the bound), cache replay and the invalidation closure after an input change compared with an independent reverse traversal, plan reproducibility.
- `scripts/reference.py`: 100 random graphs (about 1,350 tasks, including paths with spaces) driven through the planner by an independent Python harness: dependency order, bounded waves, reproducibility, the documented tie-break, and invalidation sets after an input change, a command change, a lost artifact and a forged cache entry compared with the independently computed dependent closure; failure blocking; recovery after re-executing a distrusted task.
- `scripts/scenarios.mjs`: the three proposal scenarios through the real executor in temporary workspaces, 33 checks.
- `scripts/integration.mjs`: real subprocesses with cache hits, input/output invalidation, failure propagation, timeout and retry.
- CI runs `moon check --deny-warn`, `moon fmt --check`, interface and fixture freshness checks, all of the above, and the package consumption check on demand against a registry version.

Historical proposal estimates (for example source line counts) are not release results; `scripts/stats.py` reports the actual numbers.
