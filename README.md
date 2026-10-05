# Moon TaskForge

Incremental local task execution, implemented in MoonBit with a JSON CLI and reusable library API.

- Repository: [https://github.com/123123213weqw/moon-taskforge](https://github.com/123123213weqw/moon-taskforge)
- Package: `123123213weqw/moon_taskforge@0.1.0`
- License: Apache-2.0
- Release scope: **0.1.0 initial implementation**. The broader competition proposal in `docs/proposal.md` is a reference design, not a claim that every planned capability is implemented.

## Implemented

Task identity/dependency/argv/path validation; deterministic topological ordering; cycle and output conflict rejection; producer dependency checks; canonical input/environment/dependency fingerprints; verified-output cache reuse; transitive invalidation; bounded ready waves; failed dependency blocking. scripts/execute.mjs runs real subprocesses with timeouts, retries, journals and SHA-256 file hashes.

## Build and run

Use MoonBit and Node.js 24. The core library supports JS, wasm, wasm-gc and native; the filesystem/HTTP/process CLI is JS only.

```sh
moon update
moon build --target js
moon run cmd/main --target js -- examples/scenario-1.json
node _build/js/debug/build/cmd/main/main.js examples/scenario-1.json
```

Pass `-` to read a UTF-8 JSON request from stdin. A single request must be at most 16 MiB. Successful requests print one JSON result; invalid requests exit nonzero. The host runner is a separate process and does not edit the input request file.

## Library use

```sh
moon add 123123213weqw/moon_taskforge@0.1.0
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

`execute(Json) -> Json raise` is the standard JSON boundary. `from_json`, `Value::to_json`, and `run(Value) -> Value raise` provide a typed semantic value interface. Object ordering is not significant; numeric values use finite Double. Public domain functions are listed in `pkg.generated.mbti`.

## Tests

```sh
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native  # requires a C compiler
moon build --target js
node scripts/check.mjs
python -B scripts/reference.py

node scripts/integration.mjs
```

There are 8 checked fixture cases in `tests/cases.json`, executed both in MoonBit white-box tests and through the actual Node CLI. Independent reference checks use Python's standard library or separately written algorithms. Fixtures are synthetic and are not presented as production adoption evidence. See [input and output examples](docs/usage.md) and [current boundaries](docs/boundaries.md).

## Current boundaries

Commands are argv arrays with shell=false. This is a local executor, not a security sandbox: supplied commands have the current user's rights. Cache identity includes declared inputs and explicitly supplied environment; undeclared files, executable changes and inherited environment are not hermetic. Tasks without outputs always execute. Journals record results but interrupted tasks are re-executed; side effects should be idempotent. Killing a task targets its direct child process, not every grandchild. Output diagnostics are capped at 64 KiB; cache/journal files can contain explicit environment values. Concurrent hostile workspace mutation is not isolated.

See [source and dependency attribution](THIRD_PARTY.md). This release does not establish competition eligibility or organizer acceptance.
