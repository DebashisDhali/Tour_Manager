const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.send('API is Up and Running! DB Connection is pending...');
});

// Import Routes
const userRoutes = require('./routes/userRoutes');
const tourRoutes = require('./routes/tourRoutes');
const syncRoutes = require('./routes/syncRoutes');

app.use('/users', userRoutes);
app.use('/tours', tourRoutes);
app.use('/sync', syncRoutes);

app.listen(PORT, () => {
  console.log(`🚀 Test Server is live on port ${PORT}`);
});
