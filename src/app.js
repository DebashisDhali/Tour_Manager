require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const hpp = require('hpp');
const xss = require('xss-clean');
const compression = require('compression');
const { sequelize } = require('./models');

const app = express();
const PORT = process.env.PORT || 3000;

// Trust Railway Proxy
app.set('trust proxy', 1);
app.disable('x-powered-by');

// 0. Logging & Healthcheck (Must be first)
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
  next();
});

app.get('/', (req, res) => {
  res.status(200).send('Tour Manager API is Live');
});

app.get('/health', (req, res) => res.sendStatus(200));

// --- SECURITY MIDDLEWARE ---
// 1. Helmet for Secure HTTP Headers
app.use(helmet());

// 2. Global Rate Limiting (Prevents Brute Force/DOS)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests from this IP, please try again after 15 minutes' }
});

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests from this IP, please try again after 15 minutes' }
});

app.use('/auth', authLimiter);
app.use('/ai', apiLimiter);
app.use(['/users', '/tours', '/expenses', '/sync', '/settlements', '/incomes'], apiLimiter);

// 3. Prevent HTTP Parameter Pollution
app.use(hpp());

// 4. Data Sanitization against XSS
app.use(xss());

// 5. Gzip Compression for Performance
app.use(compression());

// 1. CORS
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(cors({
  origin(origin, callback) {
    // Allow non-browser clients (mobile/native) with no origin header.
    if (!origin) return callback(null, true);
    if (allowedOrigins.length === 0) return callback(null, true);
    if (allowedOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('CORS origin not allowed'));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Origin', 'Accept', 'X-Requested-With'],
  credentials: true
}));

// 2. Body Parsers with reasonable limits
app.use(bodyParser.json({ limit: '5mb' }));
app.use(bodyParser.urlencoded({ limit: '5mb', extended: true }));

// Database Connection initialization (Safe for Serverless)
let isDbInitialized = false;
async function initDb() {
  if (isDbInitialized) return;
  try {
    console.log('🔄 Connecting to Database...');
    await sequelize.authenticate();
    console.log('✅ Database connected.');
    
    // Run schema sync with alter:true to add missing columns (like is_deleted for JoinRequest)
    // This is safe because Sequelize only adds missing columns, doesn't delete data
    console.log('🔄 Syncing schema...');
    await sequelize.sync({ alter: true });
    console.log('✅ Schema synchronized.');
    
    isDbInitialized = true;
    console.log('✅ Database ready.');
  } catch (dbErr) {
    console.error('❌ Database Connection Failed:', dbErr.message);
    // Mark initialized to avoid request storms retrying connection.
    isDbInitialized = true;
  }
}

// Ensure DB init before routes for serverless cold starts.
app.use(async (req, res, next) => {
  if (!isDbInitialized) {
    await initDb();
  }
  next();
});

// Import Routes
const userRoutes = require('./routes/userRoutes');
const tourRoutes = require('./routes/tourRoutes');
const expenseRoutes = require('./routes/expenseRoutes');
const syncRoutes = require('./routes/syncRoutes');
const settlementRoutes = require('./routes/settlementRoutes');
const programIncomeRoutes = require('./routes/programIncomeRoutes');
const authRoutes = require('./routes/authRoutes');
const aiRoutes = require('./routes/aiRoutes');
const auth = require('./middleware/auth');

app.use('/auth', authRoutes);
app.use('/users', auth, userRoutes);
app.use('/tours', auth, tourRoutes);
app.use('/expenses', auth, expenseRoutes);
app.use('/sync', auth, syncRoutes);
app.use('/settlements', auth, settlementRoutes);
app.use('/incomes', auth, programIncomeRoutes);
app.use('/ai', auth, aiRoutes);

// Global error handlers to prevent silent crashes
process.on('uncaughtException', (err) => {
  console.error('🔥 FATAL: Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('🔥 FATAL: Unhandled Rejection at:', promise, 'reason:', reason);
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
