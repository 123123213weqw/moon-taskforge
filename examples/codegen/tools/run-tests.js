// Runs the bundled application and records the outcome as the test report.
const fs = require('node:fs');
const {spawnSync} = require('node:child_process');
const result = spawnSync(process.execPath, ['build/app.js'], {encoding: 'utf8'});
fs.writeFileSync('build/test-report.txt', `exit=${result.status}\n${result.stdout}${result.stderr}`);
process.stdout.write(result.stdout); process.stderr.write(result.stderr);
process.exit(result.status);
