require('dotenv').config();
require('pg'); // Explicitly require pg so Vercel does not exclude it from the build

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
      dialect: 'sqlite',
      storage: './database.sqlite',
      logging: false
    };

module.exports = config;
