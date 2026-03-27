const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  return sequelize.define('TourMember', {
    tour_id: {
      type: DataTypes.UUID,
      primaryKey: true,
      allowNull: false
    },
    user_id: {
      type: DataTypes.UUID,
      primaryKey: true,
      allowNull: false
    },
    status: {
      type: DataTypes.STRING,
      defaultValue: 'active'
    },
    role: {
      type: DataTypes.STRING,
      defaultValue: 'viewer'
    },
    joined_at: {
      type: DataTypes.DATE,
      defaultValue: DataTypes.NOW
    },
    removed_at: {
      type: DataTypes.DATE,
      allowNull: true
    },
    meal_count: {
       type: DataTypes.DECIMAL(10, 2),
       defaultValue: 0.0
    }
  }, {
    tableName: 'TourMembers', // Keep it plural to match existing DB if any
    timestamps: true,
    createdAt: 'created_at',
    updatedAt: 'updated_at',
    indexes: [
      { unique: true, fields: ['tour_id', 'user_id'] },
      { fields: ['tour_id'] },
      { fields: ['user_id'] },
      { fields: ['updated_at'] }
    ]
  });
};
