"""Independent Python standard library oracles; deterministic synthetic data."""
import csv, datetime, hashlib, heapq, io, json, math, random, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
random.seed(20261005)
def run(request):
    result = subprocess.run(['node',str(root/'_build/js/debug/build/cmd/main/main.js'),'-'],
        input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=30)
    if result.returncode: raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)

tasks = [{'id':'a','command':['a'],'inputs':['in'],'outputs':['out']},{'id':'b','command':['b'],'deps':['a'],'inputs':['out'],'outputs':['report']}]
hashes = {'in':'one','out':'two','report':'three'}
done = run({'tasks':tasks,'hashes':hashes,'completed':{'a':'success','b':'success'}})
cached = run({'tasks':tasks,'hashes':hashes,'cache':done['cache']})
assert all(t['status']=='cached' for t in cached['tasks'])
hashes['in']='changed'
invalidated = run({'tasks':tasks,'hashes':hashes,'cache':done['cache']})
assert [t['status'] for t in invalidated['tasks']] == ['ready','waiting']
print('Task cache oracle: verified cache reuse and transitive invalidation passed')
