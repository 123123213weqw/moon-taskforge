# Version 1.0.0 boundaries

- Commands are argv arrays run with `shell=false`. The executor is a local runner, not a security sandbox: supplied commands have the current user's rights, and only the direct child process is killed on timeout or cancellation, not its grandchildren.
- Cache identity covers the command, declared input digests, declared outputs, the explicit `environment` map and the dependencies' fingerprints. Undeclared files, the executables themselves and the inherited process environment are not part of the fingerprint, so builds are reproducible only as far as they are declared.
- Tasks without declared outputs always execute, and every task that depends on them waits for them on every run.
- Invalidation is fingerprint-based without early cutoff on dependency changes: when a producer's fingerprint changes, its dependents rerun even if the produced bytes are identical. (A producer rebuilt from unchanged inputs keeps its fingerprint, so lost or tampered artifacts do not cascade.)
- Success requires an exit code of 0 and every declared output present as a regular file; outputs are not validated beyond existence and digest.
- Journals record what happened; interrupted runs are re-executed from the cache rather than resumed, so side effects should be idempotent. The journal and cache files can contain explicit environment values and bounded command output (64 KiB per attempt).
- Declared paths are relative, without `..`, drive letters or backslashes; symbolic links inside the workspace are refused. Paths may contain spaces.
- Output ownership is checked case-insensitively, which is stricter than necessary on case-sensitive file systems.
- Concurrency bounds the ready wave (1–256); it does not limit what a single command spawns. Concurrent hostile workspace mutation is not isolated.
- A single CLI request is limited to 16 MiB of UTF-8 input; timeouts range from 1 ms to 24 hours and retries from 0 to 10.
- There is no distributed scheduling, no container or cluster backend and no remote cache.
