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
      allowNull: true
    },
    email: {
      type: DataTypes.STRING,
      allowNull: true
    },
    avatar_url: {
      type: DataTypes.STRING,
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
  });
};
