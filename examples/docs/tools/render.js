// Renders each Markdown page to a minimal HTML page.
const fs = require('node:fs');
fs.mkdirSync('site', {recursive: true});
for (const name of ['intro', 'guide']) {
  const markdown = fs.readFileSync(`docs/${name}.md`, 'utf8');
  const html = markdown.split('\n').filter(Boolean).map(line =>
    line.startsWith('# ') ? `<h1>${line.slice(2)}</h1>`
      : `<p>${line.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')}</p>`).join('\n');
  fs.writeFileSync(`site/${name}.html`, html + '\n');
}
console.log('rendered 2 pages');
