const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  return sequelize.define('Settlement', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    tour_id: {
      type: DataTypes.UUID,
      allowNull: false
    },
    from_id: {
      type: DataTypes.UUID,
      allowNull: false
    },
    to_id: {
      type: DataTypes.UUID,
      allowNull: false
    },
    amount: {
      type: DataTypes.DECIMAL(10, 2),
      allowNull: false
    },
    date: {
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW
    },
    status: {
        type: DataTypes.ENUM('completed', 'pending'),
        defaultValue: 'completed'
    }
  }, {
    timestamps: true,
    createdAt: 'created_at',
    updatedAt: 'updated_at',
    indexes: [
      { fields: ['tour_id'] },
      { fields: ['updated_at'] }
    ]
  });
};
