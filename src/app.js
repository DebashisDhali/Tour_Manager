require('dotenv').config();
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
const programIncomeRoutes = require('./routes/programIncomeRoutes');
const authRoutes = require('./routes/authRoutes');
const auth = require('./middleware/auth');

app.use('/auth', authRoutes);
app.use('/users', auth, userRoutes);
app.use('/tours', auth, tourRoutes);
app.use('/expenses', auth, expenseRoutes);
app.use('/sync', auth, syncRoutes);
app.use('/settlements', auth, settlementRoutes);
app.use('/incomes', auth, programIncomeRoutes);


// Global error handlers to prevent silent crashes
process.on('uncaughtException', (err) => {
  console.error('🔥 FATAL: Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('🔥 FATAL: Unhandled Rejection at:', promise, 'reason:', reason);
});

// Database Connection initialization (Safe for Serverless)
let isDbInitialized = false;
async function initDb() {
  if (isDbInitialized) return;
  try {
    console.log('🔄 Initializing Database Connection...');
    await sequelize.authenticate();
    console.log('✅ Database connected.');
    // In production/serverless, sync { alter: true } can be slow. 
    // Usually migrations are better, but we keep it for simplicity.
    await sequelize.sync();
    console.log('✅ Database schema synced.');
    isDbInitialized = true;
  } catch (dbErr) {
    console.error('❌ Database Initialization Failed:', dbErr);
  }
}

// Global error handlers to prevent silent crashes
process.on('uncaughtException', (err) => {
  console.error('🔥 FATAL: Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('🔥 FATAL: Unhandled Rejection at:', promise, 'reason:', reason);
});

// Middleware to ensure DB is initialized
app.use(async (req, res, next) => {
  if (!isDbInitialized) {
    await initDb();
  }
  next();
});

// Helper for Railway/Local - Vercel will use exported app
if (process.env.NODE_ENV !== 'production' || !process.env.VERCEL) {
  const server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server is listening on port ${PORT}`);
    initDb(); // Background init
  });

  server.on('error', (err) => {
    console.error('❌ Server Listen Error:', err);
  });
}

// Export the Express app for Vercel
module.exports = app;
