# The three complete scenarios

Each scenario is a directory under `examples/` with a `workflow.json`, the tool scripts the tasks run (plain Node, declared as inputs so that editing a tool invalidates its task) and the input files. `node scripts/scenarios.mjs` copies every scenario into a temporary workspace, drives it through `scripts/execute.mjs` pass by pass, and checks the documented outcomes (33 checks in total). To run one by hand, copy it first — the executor writes outputs, `.taskforge-cache.json` and `.taskforge-journal.json` into the workspace:

```sh
cp -R examples/codegen /tmp/codegen
node scripts/execute.mjs /tmp/codegen/workflow.json /tmp/codegen      # first build
node scripts/execute.mjs /tmp/codegen/workflow.json /tmp/codegen      # everything cached
```

## 1. Code generation build (`examples/codegen`)

**Inputs.** `schema.json` (an entity with three fields), `tools/generate.js` (writes `generated/model.js`), `src/main.js` (validates a record against the model), `tools/bundle.js` (concatenates model and source into `build/app.js`), `tools/run-tests.js` (runs the bundle and writes `build/test-report.txt`). The graph is `generate → compile → test` with concurrency 2.

**Process.** Pass 1 builds everything. Pass 2 changes nothing. Pass 3 adds a `customer` field to the schema. Pass 4 adds the field to the record in `src/main.js`.

**Verifiable outputs.** Pass 1 executes all three tasks and the report starts with `exit=0`. Pass 2 executes nothing; every task is `cached` with reason `fingerprint and outputs verified`. Pass 3 reruns the whole chain: `generate` because `fingerprint changed: inputs`, the others because their inputs and dependency fingerprints changed; the regenerated model makes the test fail, the journal captures `record is missing fields: customer`, and `summary.rerun` is `["test"]`. Pass 4 reruns only `compile` and `test` (`generate` stays cached) and succeeds.

## 2. Documentation publishing preparation (`examples/docs`)

**Inputs.** Two Markdown pages (`docs/intro.md`, `docs/guide.md`; the guide links to a page that does not exist), `tools/render.js` (Markdown to HTML), `tools/index.js` (table of contents), `tools/linkcheck.js` (resolves every `href` against the rendered site and writes `reports/links.txt`, exit 1 on a broken link), `tools/package.js` (bundles the site and the link report into `dist/site.bundle`). The graph is `render → {index, linkcheck} → package` with concurrency 3.

**Process.** Pass 1 runs with the broken link. Pass 2 runs after the link is corrected. Pass 3 changes nothing.

**Verifiable outputs.** In pass 1 `linkcheck` fails, `package` is `blocked` with reason `dependency failed: linkcheck`, `index` still succeeds, no `dist/site.bundle` exists, the report names `guide.html -> reference.html`, the executor captured the `broken links` log, and `summary.rerun` is `["linkcheck", "package"]`. Pass 2 reruns `render`, `index`, `linkcheck` and `package`, and the bundle embeds `all links resolve`. Pass 3 executes nothing.

## 3. Offline asset processing (`examples/assets`)

**Inputs.** Six assets under `assets/` (one of them `cover art.txt`, with a space; `4.txt` is marked slow), `tools/process.js` (writes an uppercased "thumbnail"; slow assets take two seconds), `tools/manifest.js` (lists every thumbnail with its size). Six `thumb-*` tasks feed a `manifest` task; `thumb-4` has `timeout_ms: 300` and `retries: 1`; concurrency is 2.

**Process.** Pass 1 runs as is. Pass 2 runs after the slow marker is removed from `4.txt`. Pass 3 runs after `out/3.thumb` is deleted. Pass 4 runs after the cache entry of `thumb-2` is forged with a wrong output digest.

**Verifiable outputs.** Every wave in pass 1 has at most two tasks; `thumb-4` times out on both attempts and fails, the manifest is blocked, `out/cover art.thumb` is produced, and `summary.rerun` is `["thumb-4", "manifest"]`. Pass 2 executes only `thumb-4` and `manifest`, which lists six thumbnails. Pass 3 executes only `thumb-3`; the manifest stays cached because the regenerated thumbnail has the same digest and `thumb-3`'s fingerprint did not change. Pass 4 executes only `thumb-2`; the journal's initial plan explains it with `outputs changed`.
