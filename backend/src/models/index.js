const { Sequelize } = require('sequelize');
const config = require('../config/database');

let sequelize;
if (process.env.DATABASE_URL) {
  sequelize = new Sequelize(process.env.DATABASE_URL, config);
} else {
  // Local Fallback to SQLite or Local Postgres
  sequelize = new Sequelize(config.database || 'tour_expense', config.username, config.password, config);
}

const User = require('./User')(sequelize);
const Tour = require('./Tour')(sequelize);
const Expense = require('./Expense')(sequelize);
const ExpenseSplit = require('./ExpenseSplit')(sequelize);
const JoinRequest = require('./JoinRequest')(sequelize);
const Settlement = require('./Settlement')(sequelize);
const ExpensePayer = require('./ExpensePayer')(sequelize);


// Relations
User.belongsToMany(Tour, { through: 'TourMembers' });
Tour.belongsToMany(User, { through: 'TourMembers' });

Tour.hasMany(Expense, { foreignKey: 'tour_id' });
Expense.belongsTo(Tour, { foreignKey: 'tour_id' });

Tour.hasMany(Settlement, { foreignKey: 'tour_id' });
Settlement.belongsTo(Tour, { foreignKey: 'tour_id' });

User.hasMany(Expense, { foreignKey: 'payer_id' }); // kept for backward compatibility (primary payer)
Expense.belongsTo(User, { foreignKey: 'payer_id', as: 'payer' });

Expense.hasMany(ExpensePayer, { foreignKey: 'expense_id' });
ExpensePayer.belongsTo(Expense, { foreignKey: 'expense_id' });

User.hasMany(ExpensePayer, { foreignKey: 'user_id' });
ExpensePayer.belongsTo(User, { foreignKey: 'user_id', as: 'contributor' });

User.hasMany(Settlement, { foreignKey: 'from_id', as: 'OutgoingSettlements' });
User.hasMany(Settlement, { foreignKey: 'to_id', as: 'IncomingSettlements' });
Settlement.belongsTo(User, { foreignKey: 'from_id', as: 'sender' });
Settlement.belongsTo(User, { foreignKey: 'to_id', as: 'receiver' });

Expense.hasMany(ExpenseSplit, { foreignKey: 'expense_id' });
ExpenseSplit.belongsTo(Expense, { foreignKey: 'expense_id' });

User.hasMany(ExpenseSplit, { foreignKey: 'user_id' }); // User who owes
ExpenseSplit.belongsTo(User, { foreignKey: 'user_id', as: 'ower' });

module.exports = {
  sequelize,
  User,
  Tour,
  Expense,
  ExpenseSplit,
  JoinRequest,
  Settlement,
  ExpensePayer
};
