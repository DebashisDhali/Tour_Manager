const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  return sequelize.define('Expense', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    tour_id: {
      type: DataTypes.UUID,
      allowNull: false
    },
    payer_id: {
      type: DataTypes.UUID,
      allowNull: true
    },
    amount: {
      type: DataTypes.DECIMAL(10, 2),
      allowNull: false
    },
    title: {
      type: DataTypes.STRING,
      allowNull: false
    },
    category: {
        type: DataTypes.STRING, // or ENUM
        defaultValue: 'Others'
    },
    note: DataTypes.TEXT,
    mess_cost_type: {
        type: DataTypes.STRING,
        allowNull: true
    },
    date: {
        type: DataTypes.DATE,
        defaultValue: DataTypes.NOW
    },
    synced_at: {
        type: DataTypes.DATE,
        allowNull: true
    }
  }, {
    timestamps: true,
    createdAt: false,
    updatedAt: 'updated_at',
    indexes: [
      { fields: ['tour_id'] },
      { fields: ['updated_at'] }
    ]
  });
};
