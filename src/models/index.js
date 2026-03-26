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
const TourMember = require('./TourMember')(sequelize);

const ProgramIncome = require('./ProgramIncome')(sequelize);

// Relations
User.belongsToMany(Tour, { through: TourMember, foreignKey: 'user_id', otherKey: 'tour_id', onDelete: 'CASCADE' });
Tour.belongsToMany(User, { through: TourMember, foreignKey: 'tour_id', otherKey: 'user_id', onDelete: 'CASCADE' });

Tour.hasMany(Expense, { foreignKey: 'tour_id', onDelete: 'CASCADE' });
Expense.belongsTo(Tour, { foreignKey: 'tour_id' });

Tour.hasMany(Settlement, { foreignKey: 'tour_id', onDelete: 'CASCADE' });
Settlement.belongsTo(Tour, { foreignKey: 'tour_id' });

Tour.hasMany(ProgramIncome, { foreignKey: 'tour_id', onDelete: 'CASCADE' });
ProgramIncome.belongsTo(Tour, { foreignKey: 'tour_id' });

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

User.hasMany(ProgramIncome, { foreignKey: 'collected_by' });
ProgramIncome.belongsTo(User, { foreignKey: 'collected_by', as: 'collector' });

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
  ExpensePayer,
  ProgramIncome,
  TourMember
};
