const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  return sequelize.define('User', {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true
    },
    name: {
      type: DataTypes.STRING,
      allowNull: false
    },
    phone: {
      type: DataTypes.STRING,
      unique: true,
      allowNull: true
    },
    email: {
      type: DataTypes.STRING,
      unique: true,
      allowNull: true
    },
    password: {
      type: DataTypes.STRING,
      allowNull: true
    },
    avatar_url: {
      type: DataTypes.TEXT,
      allowNull: true
    },
    purpose: {
      type: DataTypes.STRING,
      allowNull: true,
      defaultValue: 'tour'
    },
    is_registered: {
        type: DataTypes.BOOLEAN,
        defaultValue: false
    }
  }, {
    timestamps: true,
    createdAt: false,
    updatedAt: 'updated_at',
    indexes: [
      { fields: ['updated_at'] },
      { fields: ['phone'] },
      { fields: ['email'] }
    ]
  });
};
