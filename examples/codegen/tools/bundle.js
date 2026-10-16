// Concatenates the generated model and the application source into one script.
const fs = require('node:fs');
fs.mkdirSync('build', {recursive: true});
fs.writeFileSync('build/app.js', fs.readFileSync('generated/model.js', 'utf8') + fs.readFileSync('src/main.js', 'utf8'));
console.log('bundled build/app.js');
