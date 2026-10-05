import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execute} from './execute.mjs';
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
  console.log('Task integration: execution, cache hit, input/output invalidation, failure propagation, timeout and retry passed');
} finally { fs.rmSync(base,{recursive:true,force:true}); }
