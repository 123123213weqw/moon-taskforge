// Produces a "thumbnail" (uppercased content) for one asset; assets marked
// slow take two seconds, longer than the configured timeout.
const fs = require('node:fs');
const name = process.argv[2];
const content = fs.readFileSync(`assets/${name}.txt`, 'utf8');
const finish = () => {
  fs.mkdirSync('out', {recursive: true});
  fs.writeFileSync(`out/${name}.thumb`, content.toUpperCase());
  console.log(`processed ${name}`);
};
if (content.startsWith('slow')) setTimeout(finish, 2000); else finish();
