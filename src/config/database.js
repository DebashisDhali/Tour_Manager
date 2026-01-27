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
      dialect: 'sqlite',
      storage: './database.sqlite',
      logging: false
    };

module.exports = config;
