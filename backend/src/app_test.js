const express = require('express');
const app = express();
const PORT = 3000; // Hardcoded for test

app.get('/', (req, res) => {
  res.send('API is Up and Running on Port 3000!');
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Test Server is live on port ${PORT}`);
});
