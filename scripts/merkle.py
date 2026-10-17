import hashlib, json
def canonical(v): return json.dumps(v, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
def digest(text): return hashlib.sha256(text.encode('utf-8')).hexdigest()
def node(task, hashes, executables, env, deps):
    """Merkle fingerprint node exactly as the planner builds it; deps maps dependency id -> its node."""
    n = {'version': 2,
         'command': digest(canonical(task['command'])),
         'inputs': digest(canonical({p: hashes.get(p) for p in task.get('inputs', [])}))}
    if task['command'][0] in executables: n['executable'] = executables[task['command'][0]]
    n['outputs'] = digest(canonical(task.get('outputs', [])))
    n['environment'] = digest(canonical(env))
    n['dependencies'] = {d: deps[d]['digest'] for d in task.get('deps', [])}
    n['digest'] = digest(canonical(n))
    return n
