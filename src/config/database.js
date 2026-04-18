require('dotenv').config();
require('pg'); // Explicitly require pg so Vercel does not exclude it from the build

const disableSslVerification = process.env.DB_SSL_REJECT_UNAUTHORIZED === 'false';

const config = process.env.DATABASE_URL 
  ? {
      dialect: 'postgres',
      dialectOptions: {
        ssl: {
          require: true,
          rejectUnauthorized: !disableSslVerification
        }
      }
    }
  : {
      dialect: 'sqlite',
      storage: './database.sqlite',
      logging: false
    };

module.exports = config;
