"""Independent follow-up oracles over synthetic deterministic inputs."""
import collections,copy,hashlib,json,math,random,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
random.seed(20261018)
def run(request, error=False):
    result=subprocess.run(['node',str(root/'_build/js/debug/build/cmd/main/main.js'),'-'],input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=60)
    if error:
        assert result.returncode==1,(result.returncode,result.stdout); return
    assert result.returncode in (0,2),(result.returncode,result.stdout,result.stderr)
    return json.loads(result.stdout)

for _ in range(20):
    tasks=[]
    for i in range(8): tasks.append({'id':str(i),'command':['echo',str(i)],'deps':[str(j) for j in range(i) if random.random()<0.3],'inputs':['file'+str(i)]})
    first=random.randrange(8); expected={str(first)}
    for task in tasks:
        if any(dep in expected for dep in task['deps']):expected.add(task['id'])
    result=run({'operation':'impact','tasks':tasks,'changed_inputs':['file'+str(first)]})
    assert {t['id'] for t in result['affected']}==expected
    assert set(result['unaffected'])=={str(i) for i in range(8)}-expected
    assert result['plan_only']
print('Task impact: 20 independent dependency closures passed')
