// Generates a model definition from schema.json.
const fs = require('node:fs');
const schema = JSON.parse(fs.readFileSync('schema.json', 'utf8'));
fs.mkdirSync('generated', {recursive: true});
fs.writeFileSync('generated/model.js',
  `// Generated from schema.json; do not edit.\nconst model = ${JSON.stringify({entity: schema.entity, fields: schema.fields})};\n`);
console.log(`generated model for ${schema.entity} with ${schema.fields.length} fields`);
