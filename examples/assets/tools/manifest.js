// Lists every produced thumbnail with its size.
const fs = require('node:fs');
const names = fs.readdirSync('out').filter(name => name.endsWith('.thumb')).sort();
fs.writeFileSync('out/manifest.txt', names.map(name => `${name} ${fs.statSync(`out/${name}`).size}`).join('\n') + '\n');
console.log(`manifest lists ${names.length} thumbnails`);
