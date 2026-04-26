const { Sequelize } = require('sequelize');
require('dotenv').config();

const sequelize = new Sequelize(process.env.DATABASE_URL, {
  dialect: 'postgres',
  dialectOptions: {
    ssl: {
      require: true,
      rejectUnauthorized: false
    }
  },
  logging: console.log
});

const models = require('./models')(sequelize);

async function migrate() {
  try {
    console.log('🚀 Starting migration...');
    
    // We use sync({ alter: true }) to add missing columns without losing data
    // In production, it's usually better to use migrations, but for this quick fix, 
    // alter: true will add the missing 'is_deleted' columns.
    await sequelize.sync({ alter: true });
    
    console.log('✅ Migration completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

migrate();
