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

// On timeout the child gets SIGTERM and, after grace milliseconds, SIGKILL; with no grace it is
// killed outright. A timed-out task is a failure whatever exit code the handler produces.
function run(command, base, environment, timeout, grace = 0, logFile) {
  return new Promise(resolve => {
    const started = Date.now();
    const child = spawn(command[0], command.slice(1), {cwd: base, env: {...process.env, ...environment}, shell: false, stdio: ['ignore','pipe','pipe']});
    children.add(child);
    let output = '', timedOut = false, error, escalation;
    // The journal keeps a bounded tail; the log file receives everything, interleaved as it arrived.
    const log = logFile ? fs.createWriteStream(logFile) : undefined;
    const collect = chunk => { output = (output + chunk.toString()).slice(-65536); log?.write(chunk); };
    child.stdout.on('data', collect); child.stderr.on('data', collect);
    child.on('error', err => { error = err.message; });
    const timer = setTimeout(() => {
      timedOut = true;
      if (grace > 0) { child.kill('SIGTERM'); escalation = setTimeout(() => child.kill('SIGKILL'), grace); }
      else child.kill('SIGKILL');
    }, timeout);
    child.on('close', (code, signal) => {
      clearTimeout(timer); clearTimeout(escalation); children.delete(child);
      const done = () => resolve({code, signal, timedOut, error, output, duration_ms: Date.now() - started});
      log ? log.end(done) : done();
    });
  });
}

// Log file name for an attempt: the id made file-safe plus a short digest so distinct ids never collide.
function logPath(base, id, attempt) {
  const safe = id.replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 64);
  return path.join(base, '.taskforge', 'logs', `${safe}-${sha256(id).slice(0, 8)}.${attempt}.log`);
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

// Everything a planning call needs that does not change during a run.
function prepare(workflow, workspace, cacheFile, options = {}) {
  const base = fs.realpathSync(workspace);
  if (!fs.statSync(base).isDirectory()) throw new Error('Workspace must be a directory');
  const targets = options.targets ?? workflow.targets;
  // Validate the complete graph before touching the workspace or executing any command.
  engine({tasks: workflow.tasks, hashes: {}, concurrency: workflow.concurrency ?? 4, ...(targets && {targets}), ...(workflow.propagate && {propagate: workflow.propagate})});
  const environment = workflow.environment ?? {};
  for (const [name, value] of Object.entries(environment)) if (typeof value !== 'string' || name.includes('=')) throw new Error('Environment must map names to strings');
  const cache = fs.existsSync(cacheFile) ? JSON.parse(fs.readFileSync(cacheFile, 'utf8')) : {};
  const executables = executableDigests(workflow, base);
  return {base, cache, environment, executables,
    fingerprintInputs: {environment: environmentDigests(environment), executables, concurrency: workflow.concurrency ?? 4,
      ...(targets && {targets}), ...(workflow.propagate && {propagate: workflow.propagate})}};
}

// Plans without executing anything or writing any file.
export function plan(workflow, workspace, cacheFile, options = {}) {
  const {base, cache, fingerprintInputs, executables} = prepare(workflow, workspace, cacheFile, options);
  const hashes = hashDeclaredFiles(workflow, base);
  return {plan: engine({tasks: workflow.tasks, hashes, cache, completed: {}, ...fingerprintInputs}), hashes, cache, executables};
}

const canonical = value => JSON.stringify(value, (key, item) =>
  item && typeof item === 'object' && !Array.isArray(item) ? Object.fromEntries(Object.keys(item).sort().map(k => [k, item[k]])) : item);

// Explains one task: its status and reason, which fingerprint fields differ from the cache
// entry, the current versus recorded output digests, and the status of its dependencies.
export function why(workflow, workspace, cacheFile, id, options = {}) {
  const {plan: current, hashes, cache} = plan(workflow, workspace, cacheFile, options);
  const report = current.tasks.find(task => task.id === id);
  if (!report) throw new Error('Unknown task: ' + id);
  const task = workflow.tasks.find(candidate => candidate.id === id);
  const entry = cache[id];
  const fields = ['inputs', 'command', 'executable', 'environment', 'dependencies', 'outputs'];
  return {
    id, status: report.status, reason: report.reason, cache_entry: Boolean(entry),
    changed_fields: entry ? fields.filter(field => canonical(entry.fingerprint?.[field] ?? null) !== canonical(report.fingerprint[field] ?? null)) : [],
    outputs: Object.fromEntries((task.outputs ?? []).map(name => [name, {current: hashes[name] ?? null, cached: entry?.outputs?.[name] ?? null}])),
    dependencies: (task.deps ?? []).map(dep => ({id: dep, status: current.tasks.find(candidate => candidate.id === dep).status})),
    fingerprint: report.fingerprint,
  };
}

// Removes files the cache records as outputs that no current task declares, and the
// cache entries of tasks that no longer exist. Only declared, cache-recorded paths inside
// the workspace are ever touched.
function pruneOrphans(workflow, base, cache) {
  const declared = new Set(workflow.tasks.flatMap(task => task.outputs ?? []));
  const current = new Set(workflow.tasks.map(task => task.id));
  const pruned = [];
  for (const [id, entry] of Object.entries(cache)) {
    for (const name of Object.keys(entry.outputs ?? {})) {
      if (declared.has(name)) continue;
      const file = safeFile(base, name);
      if (fs.existsSync(file) && fs.statSync(file).isFile()) { fs.rmSync(file); pruned.push(name); }
      delete entry.outputs[name];
    }
    if (!current.has(id)) delete cache[id];
  }
  return pruned.sort();
}

// Merges the finished work of a plan into the persisted cache; a task that failed drops its entry.
function persistCache(cacheFile, cache, plan) {
  const refreshed = {...cache, ...plan.cache};
  for (const task of plan.tasks) if (task.status === 'failed') delete refreshed[task.id];
  atomic(cacheFile, refreshed);
  return refreshed;
}

export async function execute(workflow, workspace, cacheFile, journalFile, options = {}) {
  const started = Date.now();
  const {base, cache, environment, executables, fingerprintInputs} = prepare(workflow, workspace, cacheFile, options);
  const pruned = options.prune ? pruneOrphans(workflow, base, cache) : [];
  const completed = {}, results = [], waves = [];
  let initial;
  let plan;
  const signal = options.signal;
  const stopped = () => cancelled || Boolean(signal?.aborted);
  const onAbort = () => { for (const child of children) child.kill('SIGTERM'); };
  signal?.addEventListener('abort', onAbort, {once: true});
  try {
  for (;;) {
    if (stopped()) throw new Error('Execution cancelled');
    plan = engine({tasks: workflow.tasks, hashes: hashDeclaredFiles(workflow, base), cache, completed, ...fingerprintInputs});
    // The first plan explains which tasks need work and why; later plans only report progress.
    initial ??= plan.tasks.map(({id, status, reason}) => ({id, status, reason}));
    // Finished work is persisted before the next wave, so an interrupted run keeps it.
    persistCache(cacheFile, cache, plan);
    if (plan.terminal) break;
    if (!plan.ready.length) throw new Error('Scheduler made no progress');
    const wave = {tasks: plan.ready.map(task => task.id), duration_ms: 0};
    const waveStarted = Date.now();
    waves.push(wave);
    if (options.logs !== false) fs.mkdirSync(path.join(base, '.taskforge', 'logs'), {recursive: true});
    await Promise.all(plan.ready.map(async task => {
      let outcome;
      for (let attempt = 0; attempt <= task.retries; attempt++) {
        if (stopped()) return;
        const log = options.logs !== false ? logPath(base, task.id, attempt + 1) : undefined;
        outcome = await run(task.command, base, environment, task.timeout_ms, task.grace_ms, log);
        results.push({id: task.id, attempt: attempt + 1, ...(log && {log: path.relative(base, log)}), ...outcome});
        if (outcome.code === 0 && !outcome.timedOut) break;
      }
      const outputsExist = task.outputs.every(name => {
        const file = safeFile(base, name); return fs.existsSync(file) && fs.statSync(file).isFile();
      });
      completed[task.id] = outcome?.code === 0 && !outcome?.timedOut && outputsExist ? 'success' : 'failed';
    }));
    wave.duration_ms = Date.now() - waveStarted;
    atomic(journalFile, {version: 1, initial, executables, pruned, completed, results, waves, interrupted_runs_are_reexecuted: true});
  }
  } finally { signal?.removeEventListener('abort', onAbort); }
  const duration_ms = Date.now() - started;
  atomic(journalFile, {version: 1, initial, executables, pruned, completed, results, waves, duration_ms, plan});
  return {plan, initial, executables, pruned, results, waves, duration_ms};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    let mode = 'execute', target, prune = false, targets;
    while (args[0]?.startsWith('--')) {
      const flag = args.shift();
      if (flag === '--plan') mode = 'plan';
      else if (flag === '--why') { mode = 'why'; target = args.shift(); }
      else if (flag === '--prune') prune = true;
      else if (flag === '--target') (targets ??= []).push(args.shift());
      else throw new Error('Unknown option ' + flag);
    }
    const [file, workspace = process.cwd()] = args;
    if (!file || (mode === 'why' && !target) || targets?.includes(undefined)) throw new Error('Usage: node scripts/execute.mjs [--plan | --why TASK] [--prune] [--target TASK]... workflow.json [workspace]');
    const base = fs.realpathSync(workspace);
    const workflow = JSON.parse(fs.readFileSync(file, 'utf8'));
    const cacheFile = path.join(base, '.taskforge-cache.json');
    const options = {prune, ...(targets && {targets})};
    if (mode === 'plan') {
      console.log(JSON.stringify(plan(workflow, base, cacheFile, options).plan, null, 2));
    } else if (mode === 'why') {
      console.log(JSON.stringify(why(workflow, base, cacheFile, target, options), null, 2));
    } else {
      const result = await execute(workflow, base, cacheFile, path.join(base, '.taskforge-journal.json'), options);
      console.log(JSON.stringify(result, null, 2));
      process.exitCode = result.plan.success ? 0 : 1;
    }
  } catch (err) { console.error(err.message); process.exitCode = 1; }
}
