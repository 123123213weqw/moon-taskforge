// Builds the table of contents from the rendered page titles.
const fs = require('node:fs');
const entries = ['intro', 'guide'].map(name => {
  const title = fs.readFileSync(`site/${name}.html`, 'utf8').match(/<h1>(.*)<\/h1>/)[1];
  return `<li><a href="${name}.html">${title}</a></li>`;
});
fs.writeFileSync('site/index.html', `<h1>Contents</h1>\n<ul>\n${entries.join('\n')}\n</ul>\n`);
console.log('indexed 2 pages');
