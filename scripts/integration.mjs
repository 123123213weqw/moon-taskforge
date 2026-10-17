import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execute, plan, why} from './execute.mjs';
const base = fs.mkdtempSync(path.join(os.tmpdir(), 'taskforge-integration-'));
const cache = path.join(base, 'cache.json'), journal = path.join(base, 'journal.json');
const workflow = {tasks: [
  {id:'generate', command:[process.execPath,'-e',"const fs=require('fs'); fs.writeFileSync('generated.txt',fs.readFileSync('input.txt')); fs.appendFileSync('executions.txt','g');"],inputs:['input.txt'],outputs:['generated.txt']},
  {id:'validate', deps:['generate'], command:[process.execPath,'-e',"const fs=require('fs'); fs.writeFileSync('report.txt',fs.readFileSync('generated.txt')); fs.appendFileSync('executions.txt','v');"],inputs:['generated.txt'],outputs:['report.txt']},
]};
try {
  fs.writeFileSync(path.join(base,'input.txt'),'first');
  assert.equal((await execute(workflow,base,cache,journal)).plan.success,true);
  assert.equal(fs.readFileSync(path.join(base,'report.txt'),'utf8'),'first');
  assert.equal((await execute(workflow,base,cache,journal)).results.length,0);
  assert.equal(fs.readFileSync(path.join(base,'executions.txt'),'utf8'),'gv');
  fs.writeFileSync(path.join(base,'input.txt'),'second');
  assert.equal((await execute(workflow,base,cache,journal)).results.length,2);
  assert.equal(fs.readFileSync(path.join(base,'report.txt'),'utf8'),'second');
  fs.writeFileSync(path.join(base,'report.txt'),'tampered');
  assert.equal((await execute(workflow,base,cache,journal)).results.length,1);
  const failure = {tasks:[{id:'fail',command:[process.execPath,'-e','process.exit(3)']},{id:'blocked',deps:['fail'],command:[process.execPath,'-e',"throw Error('must not execute')"]}]};
  const report = await execute(failure,base,cache,journal);
  assert.equal(report.plan.success,false); assert.equal(report.plan.tasks[1].status,'blocked');
  const timeout = await execute({tasks:[{id:'slow',command:[process.execPath,'-e','setTimeout(()=>{},10000)'],timeout_ms:50,retries:1}]},base,cache,journal);
  assert.equal(timeout.results.length,2); assert.ok(timeout.results.every(r=>r.timedOut));

  // Environment values reach the child process but only their digests reach the planner, cache and journal.
  const secret = 'fixture-secret-value-4471';
  const withEnv = {environment:{SECRET:secret},tasks:[{id:'env',command:[process.execPath,'-e',"require('fs').writeFileSync('env.txt',String(process.env.SECRET.length))"],outputs:['env.txt']}]};
  assert.equal((await execute(withEnv,base,cache,journal)).plan.success,true);
  assert.equal(fs.readFileSync(path.join(base,'env.txt'),'utf8'),String(secret.length));
  for (const file of [cache,journal]) assert.ok(!fs.readFileSync(file,'utf8').includes(secret),'raw environment value leaked into '+path.basename(file));
  assert.equal((await execute(withEnv,base,cache,journal)).results.length,0);
  const rotated = await execute({...withEnv,environment:{SECRET:secret+'-rotated'}},base,cache,journal);
  assert.equal(rotated.initial.find(t=>t.id==='env').reason,'fingerprint changed: environment');

  // With hash_executables the program itself is fingerprinted, even when it is not a declared input.
  const tool = path.join(base,'tool.sh');
  fs.writeFileSync(tool,'#!/bin/sh\nprintf one > tool-out.txt\n',{mode:0o755});
  const hashed = {hash_executables:true,tasks:[{id:'tool',command:['./tool.sh'],outputs:['tool-out.txt']}]};
  const first = await execute(hashed,base,cache,journal);
  assert.equal(first.plan.success,true); assert.match(first.executables['./tool.sh'],/^[0-9a-f]{64}$/);
  assert.equal((await execute(hashed,base,cache,journal)).results.length,0);
  fs.writeFileSync(tool,'#!/bin/sh\nprintf two > tool-out.txt\n',{mode:0o755});
  const edited = await execute(hashed,base,cache,journal);
  assert.equal(edited.initial.find(t=>t.id==='tool').reason,'fingerprint changed: executable');
  assert.equal(fs.readFileSync(path.join(base,'tool-out.txt'),'utf8'),'two');

  // --plan only looks; --why explains a task against the cache.
  fs.writeFileSync(path.join(base,'input.txt'),'third');
  const preview = plan(workflow,base,cache);
  assert.equal(preview.plan.tasks.find(t=>t.id==='generate').status,'ready');
  assert.equal(fs.readFileSync(path.join(base,'report.txt'),'utf8'),'second','plan mode must not execute');
  const explanation = why(workflow,base,cache,'generate');
  assert.deepEqual(explanation.changed_fields,['inputs']);
  assert.equal(explanation.reason,'fingerprint changed: inputs');
  assert.equal(explanation.outputs['generated.txt'].current,explanation.outputs['generated.txt'].cached,'outputs untouched so far');
  assert.deepEqual(why(workflow,base,cache,'validate').dependencies,[{id:'generate',status:'ready'}]);
  assert.throws(()=>why(workflow,base,cache,'ghost'),/Unknown task/);
  console.log('Task integration: execution, cache hit, input/output invalidation, failure propagation, timeout, retry, environment privacy, executable hashing, plan and why passed');
} finally { fs.rmSync(base,{recursive:true,force:true}); }
