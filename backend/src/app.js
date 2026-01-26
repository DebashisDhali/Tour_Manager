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

app.use('/users', userRoutes);
app.use('/tours', tourRoutes);
app.use('/expenses', expenseRoutes);
app.use('/sync', syncRoutes);


// Database Connection & Server Start
async function startServer() {
  try {
    await sequelize.authenticate();
    console.log('Database connected...');
    
    // Sync models (Alter in dev to match schema updates)
    await sequelize.sync({ alter: true });
    console.log('Database synced...');

    app.listen(PORT, () => {
      console.log(`Server running on http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('Unable to connect to the database:', err);
  }
}

startServer();
