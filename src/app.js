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


// Global error handlers to prevent silent crashes
process.on('uncaughtException', (err) => {
  console.error('🔥 FATAL: Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('🔥 FATAL: Unhandled Rejection at:', promise, 'reason:', reason);
});

// Database Connection & Server Start
async function startServer() {
  console.log(`📡 Attempting to start server on port ${PORT}...`);
  try {
    const server = app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 Server is live on port ${PORT}`);
      console.log(`📅 Started at: ${new Date().toISOString()}`);
    });

    server.on('error', (err) => {
      console.error('❌ Server Listen Error:', err);
    });

  } catch (listenError) {
    console.error('❌ Synchronous Listen Error:', listenError);
  }

  try {
    console.log('🔄 Connecting to database...');
    await sequelize.authenticate();
    console.log('✅ Database connected successfully.');
    
    // Sync models
    console.log('🔄 Syncing models...');
    await sequelize.sync();
    console.log('✅ Database schema synced.');
  } catch (err) {
    console.error('❌ Database Initialization Error:', err);
    // We don't exit(1) here to let the app stay alive for healthchecks
  }
}

startServer();
