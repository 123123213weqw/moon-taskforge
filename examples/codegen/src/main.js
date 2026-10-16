const record = {id: 1, total: 9.5, currency: 'EUR'};
const missing = model.fields.filter(field => !(field in record));
if (missing.length) {
  console.error('record is missing fields: ' + missing.join(', '));
  process.exit(1);
}
console.log('ok ' + model.entity);
