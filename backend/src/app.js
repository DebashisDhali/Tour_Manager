const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { sequelize } = require('./models');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Routes
app.get('/', (req, res) => {
  res.send('Tour Expense Manager API is running');
});

// Import Routes
const userRoutes = require('./routes/userRoutes');
const tourRoutes = require('./routes/tourRoutes');
const expenseRoutes = require('./routes/expenseRoutes');
const syncRoutes = require('./routes/syncRoutes');
const settlementRoutes = require('./routes/settlementRoutes');

app.use('/users', userRoutes);
app.use('/tours', tourRoutes);
app.use('/expenses', expenseRoutes);
app.use('/sync', syncRoutes);
app.use('/settlements', settlementRoutes);


// Database Connection & Server Start
async function startServer() {
  console.log(`📡 Starting server on port ${PORT}...`);
  app.listen(PORT, () => {
    console.log(`🚀 Server is live on port ${PORT}`);
  });

  try {
    console.log('🔄 Connecting to database...');
    await sequelize.authenticate();
    console.log('✅ Database connected successfully.');
    
    // Sync models
    await sequelize.sync();
    console.log('✅ Database schema synced.');
  } catch (err) {
    console.error('❌ Database Initialization Error:', err);
  }
}

startServer();
