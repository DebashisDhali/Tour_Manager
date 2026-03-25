const { User } = require('../models');
const { Op } = require('sequelize');

exports.createUser = async (req, res) => {
  try {
    const { id, name, phone } = req.body;
    // Insert or update to support sync
    const [user, created] = await User.upsert({
        id, name, phone, is_registered: true
    });
    res.status(201).json(user);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getAllUsers = async (req, res) => {
  try {
    const users = await User.findAll();
    res.json(users);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.searchUsers = async (req, res) => {
  try {
    const { query } = req.query;
    if (!query) return res.json([]);
    
    const users = await User.findAll({
      where: {
        [Op.or]: [
          { name: { [Op.like]: `%${query}%` } },
          { phone: { [Op.like]: `%${query}%` } }
        ]
      },
      limit: 10
    });
    res.json(users);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
