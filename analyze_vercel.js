const https = require('https');

https.get('https://tour-manager-navy.vercel.app/tours/diagnostic/db-schema', (res) => {
  let data = '';
  res.on('data', chunk => { data += chunk; });
  res.on('end', () => {
    try {
      console.log(JSON.stringify(JSON.parse(data), null, 2));
    } catch(e) {
      console.error("Failed to parse JSON:", data);
    }
  });
}).on('error', err => {
  console.log('Error: ', err.message);
});
