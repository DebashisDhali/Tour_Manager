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
app.enable('trust proxy');

// 0. Logging & Healthcheck (Must be first)
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
  next();
});

app.get('/', (req, res) => {
  res.status(200).send('Tour Manager API is Live');
});

// Diagnostic route - inspect DB schema
const { Tour, TourMember, User } = require('./models');
app.get('/tours/diagnostic/db-schema', async (req, res) => {
  try {
    const rawSchema = await require('./models').sequelize.query(
      `SELECT column_name, data_type, is_nullable, column_default 
       FROM information_schema.columns 
       WHERE table_name IN ('Tours', 'Users', 'TourMembers', 'tours', 'users', 'tourmembers')`,
      { type: require('./models').sequelize.QueryTypes.SELECT }
    );
    res.json({
      status: 'success',
      rawSchema,
      models: { Tour: Object.keys(Tour.rawAttributes) }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Diagnostic route - list all tours and their invite_codes (to debug join issue)
app.get('/tours/diagnostic/list-codes', async (req, res) => {
  try {
    const tours = await Tour.findAll({
      attributes: ['id', 'name', 'invite_code', 'created_by', 'created_at', 'updated_at'],
      order: [['updated_at', 'DESC']],
      limit: 20,
      raw: true
    });
    res.json({
      count: tours.length,
      tours: tours.map(t => ({
        id: t.id,
        name: t.name,
        invite_code: t.invite_code,
        has_invite_code: !!t.invite_code,
        created_by: t.created_by,
        updated_at: t.updated_at
      }))
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/health', (req, res) => res.sendStatus(200));

// --- SECURITY MIDDLEWARE ---
// 1. Helmet for Secure HTTP Headers
app.use(helmet());

// 2. Global Rate Limiting (Prevents Brute Force/DOS)
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 200, // Limit each IP to 200 requests per window
  message: { error: 'Too many requests from this IP, please try again after 15 minutes' }
});
app.use('/auth', limiter); // Stricter on auth
app.use('/ai', limiter);   // Protect AI billing

// 3. Prevent HTTP Parameter Pollution
app.use(hpp());

// 4. Data Sanitization against XSS
app.use(xss());

// 5. Gzip Compression for Performance
app.use(compression());

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

// Database Connection initialization (Safe for Serverless)
let isDbInitialized = false;
async function initDb() {
  if (isDbInitialized) return;
  try {
    console.log('🔄 Connecting to Database...');
    await sequelize.authenticate();
    console.log('✅ Database connected.');
    // NOTE: Do NOT use alter:true at runtime on Vercel — it's too slow and causes 10s timeout.
    // Schema is already correct from initial deployment. Only sync if truly necessary.
    isDbInitialized = true;
    console.log('✅ Database ready.');
  } catch (dbErr) {
    console.error('❌ Database Connection Failed:', dbErr.message);
    // Set initialized anyway so we don't block every request; let queries fail naturally
    isDbInitialized = true;
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
