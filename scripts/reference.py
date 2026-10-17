"""Independent Python standard library oracle; deterministic synthetic data.

One hundred random task graphs are driven to completion through the planner
and checked by a separate implementation: execution order respects every
dependency, ready waves respect the concurrency bound, the plan order is
reproducible, and the invalidation set after an input change, a command
change, a lost artifact or a forged cache entry equals the independently
computed dependent closure. Failure blocking is checked the same way.
"""
import json
import random
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
from merkle import node   # independent Merkle fingerprint computation (hashlib)
random.seed(20261016)
CLI = str(root / '_build/js/debug/build/cmd/main/main.js')


def run(request):
    result = subprocess.run(['node', CLI, '-'], input=json.dumps(request), capture_output=True,
                            text=True, encoding='utf-8', timeout=30)
    if result.returncode:
        raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)


def fails(request):
    try:
        run(request)
        return False
    except RuntimeError:
        return True


def build_graph(case):
    count = random.randint(4, 24)
    tasks = []
    for i in range(count):
        name = ('step %d' if random.random() < 0.2 else 'step-%d') % i   # some names carry spaces
        deps = sorted(random.sample(range(i), min(i, random.choice([0, 1, 1, 2, 3]))))
        task = {'id': 't%d' % i, 'command': ['tool-%d' % i, name],      # one program per task so a tool digest targets one task
                'inputs': ['src/%s.txt' % name] + ['out/t%d.bin' % d for d in deps if tasks[d].get('outputs')],
                'deps': ['t%d' % d for d in deps]}
        if random.random() < 0.9:
            task['outputs'] = ['out/t%d.bin' % i]
        tasks.append(task)
    return tasks


def closure(tasks, roots):
    """Tasks that are, or transitively depend on, any root task (independent reverse traversal)."""
    affected = set(roots)
    changed = True
    while changed:
        changed = False
        for task in tasks:
            if task['id'] not in affected and any(dep in affected for dep in task['deps']):
                affected.add(task['id'])
                changed = True
    return sorted(affected)


def utf16(text):
    return text.encode('utf-16-be')


def source_hashes(tasks):
    return {task['inputs'][0]: 'h%s' % task['id'] for task in tasks}


def drive(tasks, concurrency):
    """Report every ready task as successful until the plan is terminal; return the order and waves."""
    hashes = source_hashes(tasks)
    completed, order, waves = {}, [], 0
    while True:
        plan = run({'tasks': tasks, 'hashes': hashes, 'completed': completed, 'concurrency': concurrency})
        if plan['terminal']:
            assert plan['success']
            return order, waves, plan
        ready = [task['id'] for task in plan['ready']]
        assert 1 <= len(ready) <= concurrency
        for id in ready:
            order.append(id)
            completed[id] = 'success'
            task = next(t for t in tasks if t['id'] == id)
            for output in task.get('outputs', []):
                hashes[output] = 'o' + id
        waves += 1
        assert waves <= len(tasks)


stats = {'tasks': 0, 'waves': 0, 'spaces': 0, 'executables': 0}
for case in range(100):
    tasks = build_graph(case)
    deps = {task['id']: task['deps'] for task in tasks}
    stats['tasks'] += len(tasks)
    stats['spaces'] += sum(' ' in task['inputs'][0] for task in tasks)
    concurrency = random.randint(1, 8)
    order, waves, final = drive(tasks, concurrency)
    stats['waves'] += waves
    position = {id: i for i, id in enumerate(order)}
    assert sorted(order) == sorted(deps), case
    assert all(position[dep] < position[id] for id, needed in deps.items() for dep in needed), case
    plan_order = [task['id'] for task in final['tasks']]
    seen = set()
    for id in plan_order:                                   # the plan listing itself is a topological order
        assert all(dep in seen for dep in deps[id]), case
        seen.add(id)
    assert run({'tasks': tasks, 'concurrency': concurrency}) == run({'tasks': tasks, 'concurrency': concurrency}), case
    if all(not needed for needed in deps.values()):
        assert plan_order == sorted(deps, key=utf16), case     # ties are broken by id in UTF-16 order

    # Full cache from the completed run; then measure invalidation sets.
    hashes = source_hashes(tasks)
    for task in tasks:
        for output in task.get('outputs', []):
            hashes[output] = 'o' + task['id']
    done = run({'tasks': tasks, 'hashes': hashes, 'completed': {t['id']: 'success' for t in tasks}})
    cache = done['cache']
    # Every fingerprint node must equal the independent Merkle computation (SHA-256 over canonical JSON).
    by_id = {t['id']: t for t in tasks}
    nodes = {}
    for report in done['tasks']:
        nodes[report['id']] = node(by_id[report['id']], hashes, {}, {}, nodes)
        assert report['fingerprint'] == nodes[report['id']], (case, report['id'])
        assert len(json.dumps(report['fingerprint'])) < 2000, case     # constant size regardless of depth
    cached_ids = [t['id'] for t in tasks if t.get('outputs')]
    replay = run({'tasks': tasks, 'hashes': hashes, 'cache': cache})
    stale = sorted(t['id'] for t in replay['tasks'] if t['status'] != 'cached')
    assert stale == closure(tasks, [t['id'] for t in tasks if not t.get('outputs')]), case   # only output-less tasks rerun

    def stale_after(request):
        plan = run(request)
        return sorted(t['id'] for t in plan['tasks'] if t['status'] != 'cached'), plan

    if cached_ids:
        victim = random.choice(cached_ids)
        always = closure(tasks, [t['id'] for t in tasks if not t.get('outputs')])
        expected = closure(tasks, [victim] + always)
        task = next(t for t in tasks if t['id'] == victim)

        def reason(plan):
            # A victim behind an output-less task is waiting, not ready, so it carries no staleness reason.
            return next(t for t in plan['tasks'] if t['id'] == victim)['reason'] if victim not in always else None

        def check(stale, plan, why):
            assert stale == expected and reason(plan) in (why, None), (case, why, reason(plan))

        changed = dict(hashes, **{task['inputs'][0]: 'changed'})
        check(*stale_after({'tasks': tasks, 'hashes': changed, 'cache': cache}), 'fingerprint changed: inputs')

        edited = [dict(t, command=t['command'] + ['--flag']) if t['id'] == victim else t for t in tasks]
        check(*stale_after({'tasks': edited, 'hashes': hashes, 'cache': cache}), 'fingerprint changed: command')

        lost = {k: v for k, v in hashes.items() if k != task['outputs'][0]}
        check(*stale_after({'tasks': tasks, 'hashes': lost, 'cache': cache}), 'outputs missing')

        forged = json.loads(json.dumps(cache))
        forged[victim]['outputs'][task['outputs'][0]] = 'forged'
        check(*stale_after({'tasks': tasks, 'hashes': hashes, 'cache': forged}), 'outputs changed')

        tooling = {'tasks': tasks, 'hashes': hashes, 'cache': cache, 'executables': {task['command'][0]: 'tool-digest'}}
        check(*stale_after(tooling), 'fingerprint changed: executable')
        stats['executables'] += 1
        # Re-executing the distrusted task with identical output restores the cache for everything
        # except tasks that depend on output-less tasks, which always wait for them.
        if victim not in always:
            again = run({'tasks': tasks, 'hashes': hashes, 'cache': forged, 'completed': {victim: 'success'}})
            for report in again['tasks']:
                if report['id'] == victim:
                    assert report['status'] == 'success', case
                elif report['id'] not in always:
                    assert report['status'] == 'cached', case

        failed = run({'tasks': tasks, 'hashes': hashes, 'cache': cache, 'completed': {victim: 'failed'}})
        blocked = sorted(t['id'] for t in failed['tasks'] if t['status'] in ('failed', 'blocked'))
        assert blocked == closure(tasks, [victim]) and not failed['success'], case
        assert failed['terminal'] == set(always).issubset(blocked), case     # output-less tasks outside the failure still run
        assert failed['summary']['rerun'] == [t['id'] for t in failed['tasks'] if t['status'] in ('failed', 'blocked')], case

print('Independent task oracle: 100 graphs (%d tasks, %d waves, %d paths with spaces, %d tool-digest checks) agree on dependency order, bounded waves, reproducibility, invalidation closures, forged cache distrust, executable digests and failure blocking'
      % (stats['tasks'], stats['waves'], stats['spaces'], stats['executables']))

# --- structured large graphs -------------------------------------------------

chain = [{'id': 'c%03d' % i, 'command': ['step', str(i)], 'deps': ['c%03d' % (i - 1)] if i else [],
          'inputs': ['src/c%03d.txt' % i] + (['out/c%03d.bin' % (i - 1)] if i else []), 'outputs': ['out/c%03d.bin' % i]} for i in range(200)]
order, waves, final = drive(chain, 8)
assert order == ['c%03d' % i for i in range(200)] and waves == 200          # a chain serializes regardless of concurrency
fan = [{'id': 'leaf%03d' % i, 'command': ['make', str(i)], 'deps': [], 'inputs': ['src/leaf%03d.txt' % i], 'outputs': ['out/leaf%03d.bin' % i]} for i in range(150)]
fan.append({'id': 'root', 'command': ['join'], 'deps': [t['id'] for t in fan], 'inputs': ['src/root.txt'] + [t['outputs'][0] for t in fan], 'outputs': ['out/root.bin']})
order, waves, final = drive(fan, 8)
assert order[-1] == 'root' and waves == 20 and len(order) == 151            # 150 leaves in 19 waves of 8, then the root
print('Structured graphs: a 200-task chain and a 150-way fan-in schedule as expected; fingerprints stay constant-size')

# --- failure validation -----------------------------------------------------

assert fails({'tasks': [{'id': 'a', 'deps': ['b'], 'command': ['x']}, {'id': 'b', 'deps': ['a'], 'command': ['x']}]})   # cycle
assert fails({'tasks': [{'id': 'a', 'command': ['x'], 'outputs': ['o']}, {'id': 'b', 'command': ['x'], 'outputs': ['O']}]})  # output conflict
assert fails({'tasks': [{'id': 'a', 'command': ['x'], 'inputs': ['a b/../c']}]})                                           # unsafe path
assert fails({'tasks': [{'id': 'a', 'command': ['x'], 'outputs': ['o']}], 'hashes': {}, 'completed': {'a': 'success'}})     # success without outputs
print('Failure validation: cycle, output conflict, unsafe path and unverifiable success rejected')
