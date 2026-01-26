require('dotenv').config();

const config = process.env.DATABASE_URL 
  ? {
      dialect: 'postgres',
      dialectOptions: {
        ssl: {
          require: true,
          rejectUnauthorized: false
        }
      }
    }
  : {
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'postgres',
      database: process.env.DB_NAME || 'tour_expense',
      host: process.env.DB_HOST || 'localhost',
      dialect: 'postgres'
    };

module.exports = config;
