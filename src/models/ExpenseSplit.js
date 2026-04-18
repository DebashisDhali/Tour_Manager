const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  return sequelize.define('ExpenseSplit', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    expense_id: {
      type: DataTypes.UUID,
      allowNull: false
    },
    user_id: {
      type: DataTypes.UUID,
      allowNull: false
    },
    amount: {
      type: DataTypes.DECIMAL(10, 2),
      allowNull: false
    }
  }, {
    timestamps: true,
    createdAt: false,
    updatedAt: 'updated_at',
    indexes: [
      { fields: ['expense_id'] },
      { fields: ['user_id'] },
      { fields: ['updated_at'] }
    ]
  });
};
