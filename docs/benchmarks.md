# Recorded benchmark observations

Recorded with `python -B scripts/bench.py` on 2026-10-18 (Apple Silicon laptop, moon 0.1.20261012 / moonc v0.10.15, Node 25). Wall times are end-to-end runs including Node startup, best of three; they are recorded observations on one machine, not performance targets or guarantees.

| Case | Best wall time (ms) |
| --- | ---: |
| plan a 1000-task chain | 167 |
| plan a 1001-task fan-in (concurrency 4) | 116 |
| execute 120 trivial commands (concurrency 8) | 2401 |

Correctness at the same scale is asserted every run (`scripts/bench.py --check`, also a CI step): the chain and fan-in plans match their expected orders and waves, invalidating one input of the 1000-task chain marks exactly its dependent closure (computed independently in Python), and the 120-command executor run completes with every task successful. Fingerprint Merkle nodes keep reports constant-size, so these figures hold regardless of graph depth.
