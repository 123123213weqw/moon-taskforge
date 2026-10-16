// Verifies that every relative link points at a rendered page.
const fs = require('node:fs');
fs.mkdirSync('reports', {recursive: true});
const broken = [];
for (const name of ['intro', 'guide']) {
  const html = fs.readFileSync(`site/${name}.html`, 'utf8');
  for (const [, href] of html.matchAll(/href="([^"]+)"/g)) {
    if (!fs.existsSync(`site/${href}`)) broken.push(`${name}.html -> ${href}`);
  }
}
fs.writeFileSync('reports/links.txt', broken.length ? 'broken:\n' + broken.join('\n') + '\n' : 'all links resolve\n');
if (broken.length) { console.error('broken links: ' + broken.join(', ')); process.exit(1); }
console.log('all links resolve');
