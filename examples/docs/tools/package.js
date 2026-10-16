// Bundles the verified site into a single publishable artifact.
const fs = require('node:fs');
fs.mkdirSync('dist', {recursive: true});
const pages = ['index', 'intro', 'guide'].map(name => `--- ${name}.html ---\n` + fs.readFileSync(`site/${name}.html`, 'utf8'));
fs.writeFileSync('dist/site.bundle', pages.join('') + '--- link report ---\n' + fs.readFileSync('reports/links.txt', 'utf8'));
console.log('packaged dist/site.bundle');
