import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execute, plan, why, status} from './execute.mjs';
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

  // A grace period lets a timed-out process clean up on SIGTERM before SIGKILL; without one it is killed outright.
  const trap = "process.on('SIGTERM',()=>{require('fs').writeFileSync(process.argv[1],'cleaned');process.exit(0)});setTimeout(()=>{},10000)";
  const graceful = await execute({tasks:[
    {id:'polite',command:[process.execPath,'-e',trap,'polite.txt'],timeout_ms:200,grace_ms:2000},
    {id:'abrupt',command:[process.execPath,'-e',trap,'abrupt.txt'],timeout_ms:200}]},base,cache,journal);
  assert.ok(graceful.results.every(r=>r.timedOut) && !graceful.plan.success,'timed-out tasks fail even when the handler exits 0');
  assert.equal(fs.readFileSync(path.join(base,'polite.txt'),'utf8'),'cleaned','SIGTERM handler ran within the grace period');
  assert.ok(!fs.existsSync(path.join(base,'abrupt.txt')),'no grace means SIGKILL before any handler');

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

  // --target limits the run to a task and its dependencies; the rest is skipped and left alone.
  fs.writeFileSync(path.join(base,'input.txt'),'targeted');
  const targeted = await execute(workflow,base,cache,journal,{targets:['generate']});
  assert.deepEqual(targeted.results.map(r=>r.id),['generate']);
  assert.deepEqual(targeted.plan.summary.skipped,['validate']);
  assert.equal(fs.readFileSync(path.join(base,'report.txt'),'utf8'),'second','skipped task did not run');
  assert.equal(targeted.plan.success,true);

  // --status summarizes the last journal: failures, waves and interruption.
  const failing = {tasks:[
    {id:'broken',command:[process.execPath,'-e','process.exit(4)'],outputs:['broken.txt']},
    {id:'after',deps:['broken'],command:[process.execPath,'-e','0']}]};
  const failedRun = await execute(failing,base,cache,journal);
  assert.equal(failedRun.plan.success,false);
  const summary = status(base, journal);
  assert.deepEqual(summary.failures.map(f => f.id + ':' + f.code),['broken:4']);
  assert.equal(summary.interrupted,false);
  assert.ok(summary.waves.length >= 1 && summary.needs_work.some(t => t.id === 'broken'));
  const controller2 = new AbortController();
  const slowBroken = {tasks:[
    {id:'first',command:[process.execPath,'-e',"require('fs').writeFileSync('first.txt','x')"],outputs:['first.txt']},
    {id:'slow2',deps:['first'],command:[process.execPath,'-e','setTimeout(()=>{},5000)']}]};
  assert.equal((await execute(slowBroken,base,cache,journal)).plan.success,true,'first pass completes so first is cached');
  const running2 = execute(slowBroken,base,cache,journal,{signal:controller2.signal});
  await new Promise(r => setTimeout(r, 400));
  controller2.abort();
  await assert.rejects(running2,/Execution cancelled/);
  const interrupted = status(base, journal);
  assert.equal(interrupted.interrupted,true,'mid-run journal has no final plan');

  // Every attempt's complete output goes to a log file; the journal keeps a bounded tail.
  const chatty = await execute({tasks:[{id:'chat ty/1',command:[process.execPath,'-e',"process.stdout.write('x'.repeat(200000));process.stderr.write('END')"]}]},base,cache,journal);
  const [attempt] = chatty.results;
  assert.ok(attempt.output.length <= 65536 && attempt.output.endsWith('END'),'journal output is a bounded tail');
  assert.match(attempt.log,/^\.taskforge\/logs\/chat_ty_1-[0-9a-f]{8}\.1\.log$/);
  assert.equal(fs.statSync(path.join(base,attempt.log)).size,200003,'log file holds the full output');
  const quiet = await execute({tasks:[{id:'quiet',command:[process.execPath,'-e','0']}]},base,cache,journal,{logs:false});
  assert.ok(!('log' in quiet.results[0]),'logs can be disabled');

  // Cancellation through an AbortSignal stops the run, and the cache already holds the finished wave.
  const twoWaves = {tasks:[
    {id:'fast',command:[process.execPath,'-e',"require('fs').writeFileSync('fast.txt','done')"],outputs:['fast.txt']},
    {id:'slow',deps:['fast'],command:[process.execPath,'-e',"setTimeout(()=>require('fs').writeFileSync('slow.txt','late'),5000)"],inputs:['fast.txt'],outputs:['slow.txt']}]};
  const controller = new AbortController();
  const running = execute(twoWaves,base,cache,journal,{signal:controller.signal});
  while (!fs.existsSync(path.join(base,'fast.txt'))) await new Promise(r=>setTimeout(r,20));
  await new Promise(r=>setTimeout(r,200));
  controller.abort();
  await assert.rejects(running,/Execution cancelled/);
  assert.ok('fast' in JSON.parse(fs.readFileSync(cache,'utf8')),'finished wave persisted before cancellation');
  assert.ok(!fs.existsSync(path.join(base,'slow.txt')),'cancelled task produced nothing');
  const resumed = await execute(twoWaves,base,cache,journal);
  assert.deepEqual(resumed.results.map(r=>r.id),['slow'],'only the interrupted task runs again');
  assert.equal(resumed.plan.success,true);

  // --prune removes outputs the cache remembers for tasks that no longer exist, and nothing else.
  assert.equal((await execute(workflow,base,cache,journal)).plan.success,true);
  const trimmed = {tasks:[workflow.tasks[0]]};               // validate (and report.txt) is gone from the workflow
  fs.writeFileSync(path.join(base,'unrelated.txt'),'keep');
  const pruneRun = await execute(trimmed,base,cache,journal,{prune:true});
  assert.deepEqual(pruneRun.pruned,['env.txt','fast.txt','first.txt','report.txt','slow.txt','tool-out.txt'],'every cache-recorded output no current task declares');
  assert.ok(!fs.existsSync(path.join(base,'report.txt')) && fs.existsSync(path.join(base,'unrelated.txt')) && fs.existsSync(path.join(base,'generated.txt')));
  assert.ok(!('validate' in JSON.parse(fs.readFileSync(cache,'utf8'))),'cache entry of the removed task is dropped');
  assert.equal(pruneRun.results.length,0,'the remaining task stays cached');
  assert.ok(pruneRun.duration_ms>=0 && Array.isArray(pruneRun.waves));
  console.log('Task integration: execution, cache hit, input/output invalidation, failure propagation, timeout, graceful termination, retry, environment privacy, executable hashing, plan, why, status, log files, cancellation and prune passed');
} finally { fs.rmSync(base,{recursive:true,force:true}); }
