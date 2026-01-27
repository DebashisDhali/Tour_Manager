const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { sequelize } = require('./models');

const app = express();
const PORT = process.env.PORT || 3000;

// Trust Railway Proxy
app.enable('trust proxy');

// 0. Logging & Healthcheck (Must be first)
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
  next();
});

app.get('/', (req, res) => {
  res.status(200).send('Tour Manager API is Live');
});

app.get('/health', (req, res) => res.sendStatus(200));

// 1. CORS
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Origin', 'Accept', 'X-Requested-With'],
  credentials: true
}));

// 2. Body Parsers with increased limits for large sync payloads
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ limit: '50mb', extended: true }));

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
  try {
    // Start listening IMMEDIATELY to satisfy Railway healthchecks
    const server = app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 Server is listening on port ${PORT}`);
    });

    server.on('error', (err) => {
      console.error('❌ Server Listen Error:', err);
    });

    // Initialize Database asynchronously
    console.log('🔄 Initializing Database...');
    try {
      await sequelize.authenticate();
      console.log('✅ Database connected.');
      await sequelize.sync();
      console.log('✅ Database schema synced.');
    } catch (dbErr) {
      console.error('❌ Database Sync Failed:', dbErr);
      // Don't exit, let healthcheck pass so we can debug via logs
    }

  } catch (startupErr) {
    console.error('💥 Critical Startup Error:', startupErr);
    process.exit(1);
  }
}

startServer();
