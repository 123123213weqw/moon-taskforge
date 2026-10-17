import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {engine, safeFile} from './engine.mjs';

const children = new Set();
let cancelled = false;
function cancel() { cancelled = true; for (const child of children) child.kill('SIGTERM'); }
process.on('SIGINT', cancel);
process.on('SIGTERM', cancel);

function atomic(file, value) {
  const tmp = file + '.' + randomUUID() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2), {flag: 'wx'});
  fs.renameSync(tmp, file);
}

function run(command, base, environment, timeout) {
  return new Promise(resolve => {
    const started = Date.now();
    const child = spawn(command[0], command.slice(1), {cwd: base, env: {...process.env, ...environment}, shell: false, stdio: ['ignore','pipe','pipe']});
    children.add(child);
    let output = '', timedOut = false, error;
    // Keep bounded diagnostics while continuously draining pipes.
    const collect = chunk => { output = (output + chunk.toString()).slice(-65536); };
    child.stdout.on('data', collect); child.stderr.on('data', collect);
    child.on('error', err => { error = err.message; });
    const timer = setTimeout(() => { timedOut = true; child.kill('SIGKILL'); }, timeout);
    child.on('close', (code, signal) => {
      clearTimeout(timer); children.delete(child);
      resolve({code, signal, timedOut, error, output, duration_ms: Date.now() - started});
    });
  });
}

const sha256 = data => createHash('sha256').update(data).digest('hex');

function hashDeclaredFiles(workflow, base) {
  const hashes = {};
  for (const task of workflow.tasks) for (const name of [...(task.inputs ?? []), ...(task.outputs ?? [])]) {
    const file = safeFile(base, name);
    if (fs.existsSync(file)) {
      if (!fs.statSync(file).isFile()) throw new Error('Declared path must be a regular file');
      hashes[name] = sha256(fs.readFileSync(file));
    }
  }
  return hashes;
}

// A program with a path separator is taken relative to the workspace (or absolute);
// a bare name is searched on PATH like a POSIX shell would.
function resolveExecutable(program, base) {
  const isFile = file => { try { return fs.statSync(file).isFile(); } catch { return false; } };
  if (program.includes('/') || program.includes(path.sep)) {
    const file = path.isAbsolute(program) ? program : path.resolve(base, program);
    return isFile(file) ? file : undefined;
  }
  for (const dir of (process.env.PATH ?? '').split(path.delimiter)) {
    if (dir && isFile(path.join(dir, program))) return path.join(dir, program);
  }
  return undefined;
}

export function executableDigests(workflow, base) {
  const digests = {};
  if (!workflow.hash_executables) return digests;
  for (const task of workflow.tasks) {
    const program = task.command[0];
    if (program in digests) continue;
    const file = resolveExecutable(program, base);
    if (file) digests[program] = sha256(fs.readFileSync(file));
  }
  return digests;
}

// The planner, cache and journal only ever see digests of environment values.
function environmentDigests(environment) {
  return Object.fromEntries(Object.entries(environment).map(([name, value]) => [name, sha256(value)]));
}

export async function execute(workflow, workspace, cacheFile, journalFile) {
  const base = fs.realpathSync(workspace);
  if (!fs.statSync(base).isDirectory()) throw new Error('Workspace must be a directory');
  // Validate the complete graph before executing any command.
  engine({tasks: workflow.tasks, hashes: {}, concurrency: workflow.concurrency ?? 4});
  const cache = fs.existsSync(cacheFile) ? JSON.parse(fs.readFileSync(cacheFile, 'utf8')) : {};
  const completed = {}, results = [], waves = [];
  let initial;
  const environment = workflow.environment ?? {};
  for (const [name, value] of Object.entries(environment)) if (typeof value !== 'string' || name.includes('=')) throw new Error('Environment must map names to strings');
  const executables = executableDigests(workflow, base);
  const fingerprintInputs = {environment: environmentDigests(environment), executables, concurrency: workflow.concurrency ?? 4};
  let plan;
  for (;;) {
    if (cancelled) throw new Error('Execution cancelled');
    plan = engine({tasks: workflow.tasks, hashes: hashDeclaredFiles(workflow, base), cache, completed, ...fingerprintInputs});
    // The first plan explains which tasks need work and why; later plans only report progress.
    initial ??= plan.tasks.map(({id, status, reason}) => ({id, status, reason}));
    if (plan.terminal) break;
    if (!plan.ready.length) throw new Error('Scheduler made no progress');
    waves.push(plan.ready.map(task => task.id));
    await Promise.all(plan.ready.map(async task => {
      let outcome;
      for (let attempt = 0; attempt <= task.retries; attempt++) {
        if (cancelled) return;
        outcome = await run(task.command, base, environment, task.timeout_ms);
        results.push({id: task.id, attempt: attempt + 1, ...outcome});
        if (outcome.code === 0 && !outcome.timedOut) break;
      }
      const outputsExist = task.outputs.every(name => {
        const file = safeFile(base, name); return fs.existsSync(file) && fs.statSync(file).isFile();
      });
      completed[task.id] = outcome?.code === 0 && !outcome?.timedOut && outputsExist ? 'success' : 'failed';
    }));
    atomic(journalFile, {version: 1, initial, executables, completed, results, waves, interrupted_runs_are_reexecuted: true});
  }
  atomic(cacheFile, plan.cache);
  atomic(journalFile, {version: 1, initial, executables, completed, results, waves, plan});
  return {plan, initial, executables, results, waves};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [file, workspace = process.cwd()] = process.argv.slice(2);
    if (!file) throw new Error('Usage: node scripts/execute.mjs workflow.json [workspace]');
    const base = fs.realpathSync(workspace);
    const result = await execute(JSON.parse(fs.readFileSync(file, 'utf8')), base,
      path.join(base, '.taskforge-cache.json'), path.join(base, '.taskforge-journal.json'));
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.plan.success ? 0 : 1;
  } catch (err) { console.error(err.message); process.exitCode = 1; }
}
