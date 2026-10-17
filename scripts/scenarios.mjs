// Runs the three complete scenarios in examples/ through the real executor in
// temporary workspaces and checks their documented outcomes.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {execute} from './execute.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let checks = 0;
function expect(condition, message) { assert.ok(condition, message); checks++; }

async function scenario(name, body) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), `taskforge-${name}-`));
  try {
    fs.cpSync(path.join(root, 'examples', name), base, {recursive: true});
    const workflow = JSON.parse(fs.readFileSync(path.join(base, 'workflow.json'), 'utf8'));
    const cache = path.join(base, '.taskforge-cache.json'), journal = path.join(base, '.taskforge-journal.json');
    const pass = () => execute(workflow, base, cache, journal);
    const read = file => fs.readFileSync(path.join(base, file), 'utf8');
    const write = (file, text) => fs.writeFileSync(path.join(base, file), text);
    const status = (plan, id) => plan.tasks.find(task => task.id === id);
    const executed = result => [...new Set(result.results.map(r => r.id))].sort();
    await body({base, pass, read, write, status, executed, cache, journal});
  } finally { fs.rmSync(base, {recursive: true, force: true}); }
}

await scenario('codegen', async ({pass, read, write, status, executed}) => {
  const first = await pass();
  expect(first.plan.success && executed(first).join() === 'compile,generate,test', 'first build runs the whole pipeline');
  expect(read('build/test-report.txt').startsWith('exit=0\nok Order'), 'generated model drives the application test');

  const replay = await pass();
  expect(replay.results.length === 0 && replay.plan.tasks.every(t => t.status === 'cached'), 'unchanged inputs are fully cached');
  expect(replay.plan.tasks.every(t => t.reason === 'fingerprint and outputs verified'), 'cache hits explain their verification');

  write('schema.json', JSON.stringify({entity: 'Order', fields: ['id', 'total', 'currency', 'customer']}));
  const schemaChange = await pass();
  expect(executed(schemaChange).join() === 'compile,generate,test', 'a schema change propagates through generate, compile and test');
  expect(status(schemaChange.plan, 'test').status === 'failed' && !schemaChange.plan.success, 'the regenerated model breaks the application test');
  expect(schemaChange.results.find(r => r.id === 'test').output.includes('missing fields: customer'), 'failure output is captured in the journal');
  expect(schemaChange.plan.summary.rerun.join() === 'test', 'rerun scope names only the failed task');
  const journal = JSON.parse(read('.taskforge-journal.json'));
  expect(journal.initial.find(t => t.id === 'generate').reason === 'fingerprint changed: inputs', 'journal records why generate was rebuilt');

  write('src/main.js', read('src/main.js').replace("currency: 'EUR'", "currency: 'EUR', customer: 'acme'"));
  const fix = await pass();
  expect(executed(fix).join() === 'compile,test' && fix.plan.success, 'fixing the source reruns only compile and test');
  expect(status(fix.plan, 'generate').status === 'cached', 'generate stays cached after a source-only change');
  expect(fix.initial.find(t => t.id === 'compile').reason === 'fingerprint changed: inputs', 'compile explains its rebuild');

  write('schema.json', JSON.stringify(JSON.parse(read('schema.json')), null, 4));
  const cosmetic = await pass();
  expect(executed(cosmetic).join() === 'generate' && cosmetic.plan.success, 'a whitespace-only schema change reruns only generate');
  expect(status(cosmetic.plan, 'compile').status === 'cached' && status(cosmetic.plan, 'test').status === 'cached', 'identical generated output stops the rebuild (content propagation)');
});

await scenario('docs', async ({pass, read, write, status, executed, base}) => {
  const first = await pass();
  expect(!first.plan.success && status(first.plan, 'linkcheck').status === 'failed', 'link check fails on the broken reference');
  expect(status(first.plan, 'package').status === 'blocked' && status(first.plan, 'package').reason === 'dependency failed: linkcheck', 'packaging is blocked by the failed check');
  expect(status(first.plan, 'index').status === 'success', 'independent sibling work still completes');
  expect(!fs.existsSync(path.join(base, 'dist/site.bundle')), 'no publishable artifact is produced');
  expect(read('reports/links.txt').includes('guide.html -> reference.html'), 'report names the broken link');
  expect(first.results.find(r => r.id === 'linkcheck').output.includes('broken links'), 'executor captures the error log');
  expect(first.plan.summary.rerun.join() === 'linkcheck,package', 'rerun scope is the failed check and everything behind it');

  write('docs/guide.md', read('docs/guide.md').replace('[reference](reference.html)', '[introduction](intro.html)'));
  const fixed = await pass();
  expect(fixed.plan.success && executed(fixed).join() === 'index,linkcheck,package,render', 'fixing the page reruns render and everything downstream');
  expect(read('dist/site.bundle').includes('all links resolve'), 'published bundle embeds the clean link report');

  const replay = await pass();
  expect(replay.results.length === 0 && replay.plan.success, 'publishing is idempotent once clean');
});

await scenario('assets', async ({pass, read, write, status, executed, base, cache}) => {
  const first = await pass();
  expect(first.waves.every(wave => wave.tasks.length <= 2), 'no wave exceeds the concurrency bound of 2');
  expect(first.duration_ms >= first.waves.reduce((sum, wave) => sum + wave.duration_ms, 0) && first.waves.every(wave => wave.duration_ms >= 0), 'run duration covers every wave');
  const attempts = first.results.filter(r => r.id === 'thumb-4');
  expect(attempts.length === 2 && attempts.every(r => r.timedOut), 'the slow asset times out on both attempts');
  expect(status(first.plan, 'thumb-4').status === 'failed' && status(first.plan, 'manifest').status === 'blocked', 'timeout fails the task and blocks the manifest');
  expect(status(first.plan, 'thumb-cover-art').status === 'success' && read('out/cover art.thumb') === 'ASSET COVER ART CONTENT\n', 'paths with spaces are processed');
  expect(first.plan.summary.rerun.join() === 'thumb-4,manifest', 'recovery record lists the work left in execution order');

  write('assets/4.txt', 'asset 4 content\n');
  const recovered = await pass();
  expect(executed(recovered).join() === 'manifest,thumb-4' && recovered.plan.success, 'only the failed asset and the manifest run after the fix');
  expect(read('out/manifest.txt').split('\n').filter(Boolean).length === 6, 'manifest lists all six thumbnails');

  fs.rmSync(path.join(base, 'out/3.thumb'));
  const lost = await pass();
  expect(executed(lost).join() === 'thumb-3' && lost.plan.success, 'a lost artifact rebuilds only its producer');
  expect(status(lost.plan, 'manifest').status === 'cached', 'identical regeneration leaves the manifest cached');

  const forged = JSON.parse(fs.readFileSync(cache, 'utf8'));
  forged['thumb-2'].outputs['out/2.thumb'] = 'forged';
  fs.writeFileSync(cache, JSON.stringify(forged));
  const distrust = await pass();
  expect(executed(distrust).join() === 'thumb-2' && distrust.plan.success, 'a forged cache entry is rebuilt instead of trusted');
  expect(JSON.parse(read('.taskforge-journal.json')).initial.find(t => t.id === 'thumb-2').reason === 'outputs changed', 'journal explains the distrust');
});

console.log('Scenarios passed: code generation build, documentation publishing, offline asset processing;', checks, 'checks');
