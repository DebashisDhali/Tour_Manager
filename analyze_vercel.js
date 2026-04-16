const https = require('https');

https.get('https://tour-manager-navy.vercel.app/tours/diagnostic/db-schema', (res) => {
  let data = '';
  res.on('data', chunk => { data += chunk; });
  res.on('end', () => {
    try {
      const json = JSON.parse(data);
      // Group by what appears to be each table (heuristic: look for tell-tale columns)
      const schema = json.rawSchema;
      
      // Find columns per table based on unique column combinations
      const columns = schema.map(c => c.column_name);
      console.log("=== ALL COLUMNS IN DB ===");
      console.log(columns.join('\n'));
      console.log("\n=== FULL MODEL FIELDS (Tour) ===");
      console.log(json.models.Tour.join('\n'));
      console.log("\n=== invite_code present? ===", columns.includes('invite_code'));
      console.log("=== created_by present? ===", columns.includes('created_by'));
      console.log("=== status present? ===", columns.includes('status'));
      console.log("\n=== RAW SCHEMA (invite_code rows) ===");
      schema.filter(c => c.column_name === 'invite_code').forEach(c => console.log(JSON.stringify(c)));
      schema.filter(c => c.column_name === 'created_by').forEach(c => console.log(JSON.stringify(c)));
    } catch(e) {
      console.error("Failed to parse:", data.substring(0, 500));
    }
  });
}).on('error', err => console.log('Error: ', err.message));
