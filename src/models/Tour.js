const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  return sequelize.define('Tour', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    name: {
      type: DataTypes.STRING,
      allowNull: false
    },
    invite_code: {
      type: DataTypes.STRING,
      unique: true
    },
    start_date: {
      type: DataTypes.DATE,
      allowNull: true
    },
    end_date: {
      type: DataTypes.DATE,
      allowNull: true
    },
    created_by: {
        type: DataTypes.UUID,
        allowNull: false
    },
    created_at: {
      type: DataTypes.DATE,
      allowNull: false,
      defaultValue: DataTypes.NOW
    },
    updated_at: {
      type: DataTypes.DATE,
      allowNull: false,
      defaultValue: DataTypes.NOW
    },
    purpose: {
        type: DataTypes.STRING,
        defaultValue: 'tour'
    },
    status: {
        type: DataTypes.ENUM('active', 'completed'),
        defaultValue: 'active'
    }
  }, {
    timestamps: false,
    indexes: [
      { fields: ['created_by'] },
      { fields: ['purpose'] },
      { fields: ['status'] },
      { unique: true, fields: ['invite_code'] }
    ]
  });
};
