"""Scale validation and throughput benchmarks with deterministic synthetic data.

    python -B scripts/bench.py          # correctness at scale + timing table (best of three)
    python -B scripts/bench.py --check  # correctness only, for CI

Timings are end-to-end CLI runs (node startup included) on this machine;
they are recorded observations, not performance targets. The large plans
are checked against independent closures computed in Python, and a real
executor run of trivial commands measures scheduling overhead.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
from reference import closure   # independent dependent-closure computation, reused read-only
CLI = str(root / '_build/js/debug/build/cmd/main/main.js')


def run(request):
    result = subprocess.run(['node', CLI, '-'], input=json.dumps(request), capture_output=True,
                            text=True, encoding='utf-8', timeout=300)
    if result.returncode:
        raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)


def chain(n):
    return [{'id': 'c%04d' % i, 'command': ['step', str(i)], 'deps': ['c%04d' % (i - 1)] if i else [],
             'inputs': ['src/c%04d.txt' % i] + (['out/c%04d.bin' % (i - 1)] if i else []),
             'outputs': ['out/c%04d.bin' % i]} for i in range(n)]


def fan(n):
    leaves = [{'id': 'leaf%04d' % i, 'command': ['make', str(i)], 'inputs': ['src/leaf%04d.txt' % i],
               'outputs': ['out/leaf%04d.bin' % i]} for i in range(n)]
    return leaves + [{'id': 'root', 'command': ['join'], 'deps': [t['id'] for t in leaves],
                      'inputs': ['src/root.txt'] + [t['outputs'][0] for t in leaves], 'outputs': ['out/root.bin']}]


def hashes_of(tasks):
    return {path: 'h%04d' % (i % 97) for i, path in enumerate(sorted({p for t in tasks for p in t['inputs'] + t['outputs']}))}


def measure(label, request, expect=None):
    best = None
    result = None
    for _ in range(1 if os.environ.get('BENCH_ONCE') else 3):
        start = time.perf_counter()
        result = run(request)
        elapsed = (time.perf_counter() - start) * 1000
        best = elapsed if best is None else min(best, elapsed)
    if expect is not None:
        expect(result)
    return label, best


def main():
    check_only = '--check' in sys.argv
    rows = []

    big_chain, big_fan = chain(1000), fan(1000)
    chain_hashes, fan_hashes = hashes_of(big_chain), hashes_of(big_fan)

    def expect_chain(plan):
        assert [t['id'] for t in plan['tasks']] == [t['id'] for t in big_chain]      # topological order
        assert all(t['status'] == 'ready' for t in plan['tasks'][:1]) and plan['tasks'][0]['reason'] == 'no cache entry'
        assert all(t['status'] == 'waiting' for t in plan['tasks'][1:])

    rows.append(measure('plan a 1000-task chain', {'tasks': big_chain, 'hashes': chain_hashes}, expect_chain))

    def expect_fan(plan):
        assert plan['summary']['ready'] == ['leaf%04d' % i for i in range(4)]   # concurrency 4
        assert plan['tasks'][-1]['id'] == 'root' and plan['tasks'][-1]['status'] == 'waiting'
        assert len(plan['summary']['waiting']) == 997

    rows.append(measure('plan a 1001-task fan-in (concurrency 4)', {'tasks': big_fan, 'hashes': fan_hashes, 'concurrency': 4}, expect_fan))

    # Invalidation at scale: changing one leaf input must mark exactly its dependent closure.
    done = run({'tasks': big_chain, 'hashes': chain_hashes, 'completed': {t['id']: 'success' for t in big_chain}})
    changed = dict(chain_hashes, **{'src/c0500.txt': 'changed'})
    invalidated = run({'tasks': big_chain, 'hashes': changed, 'cache': done['cache']})
    stale = sorted(t['id'] for t in invalidated['tasks'] if t['status'] != 'cached')
    assert stale == sorted(closure(big_chain, ['c0500'])), 'invalidation set equals the dependent closure'
    rows.append(('invalidate one input of the 1000-task chain', None))

    # Executor overhead: 120 trivial commands through the real executor at concurrency 8.
    with tempfile.TemporaryDirectory(prefix='taskforge-bench-') as base:
        workflow = {'concurrency': 8, 'tasks': [
            {'id': 'noop%03d' % i, 'command': ['node', '-e', "require('fs').writeFileSync('out%03d.txt','x')".replace('%03d', '%03d' % i)],
             'inputs': ['in%03d.txt' % i], 'outputs': ['out%03d.txt' % i]} for i in range(120)]}
        for i in range(120):
            (Path(base) / ('in%03d.txt' % i)).write_text('x')
        workflow_file = Path(base) / 'bench-workflow.json'
        workflow_file.write_text(json.dumps(workflow))
        start = time.perf_counter()
        result = subprocess.run(['node', str(root / 'scripts/execute.mjs'), str(workflow_file), base],
                                capture_output=True, text=True, timeout=300)
        rows.append(('execute 120 trivial commands (concurrency 8)', (time.perf_counter() - start) * 1000))
        if result.returncode:
            raise RuntimeError(result.stderr)
        plan = json.loads(result.stdout)['plan']
        assert plan['success'] and len(plan['tasks']) == 120 and plan['summary']['success'] == ['noop%03d' % i for i in range(120)]

    if check_only:
        print('Scale check passed: 1000-task chain and fan-in plans, closure-exact invalidation and a 120-command executor run')
        return
    print('| Case | Best wall time (ms) |')
    print('| --- | ---: |')
    for label, elapsed in rows:
        print('| %s | %s |' % (label, 'n/a' if elapsed is None else '%.0f' % elapsed))
    print()
    print('End-to-end runs (node startup included), best of three, on this machine; recorded observations, not targets.')


if __name__ == '__main__':
    main()
