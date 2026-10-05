# Implemented architecture

## Core

Task identity/dependency/argv/path validation; deterministic topological ordering; cycle and output conflict rejection; producer dependency checks; canonical input/environment/dependency fingerprints; verified-output cache reuse; transitive invalidation; bounded ready waves; failed dependency blocking. scripts/execute.mjs runs real subprocesses with timeouts, retries, journals and SHA-256 file hashes.

## Boundaries

Commands are argv arrays with shell=false. This is a local executor, not a security sandbox: supplied commands have the current user's rights. Cache identity includes declared inputs and explicitly supplied environment; undeclared files, executable changes and inherited environment are not hermetic. Tasks without outputs always execute. Journals record results but interrupted tasks are re-executed; side effects should be idempotent. Killing a task targets its direct child process, not every grandchild. Output diagnostics are capped at 64 KiB; cache/journal files can contain explicit environment values. Concurrent hostile workspace mutation is not isolated.

## Integration

The core accepts semantic values and returns deterministic JSON-shaped reports. Host adapters handle files, network or processes; they invoke the compiled MoonBit engine. The CLI package declares `supported_targets = "js"`; other backends test the portable core.

## Validation evidence

Fixture cases are hand-checked assertions. Independent reference checks and integration scripts are runnable from a clean checkout. CI executes four core backends and host checks. Historical proposal targets are not release results.
