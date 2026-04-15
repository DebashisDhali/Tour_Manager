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
    if (!query || query.trim().length === 0) return res.json([]);
    
    const searchTerm = query.trim();

    const users = await User.findAll({
      where: {
        [Op.or]: [
          { name: { [Op.iLike]: `%${searchTerm}%` } },
          { phone: { [Op.iLike]: `%${searchTerm}%` } },
          { email: { [Op.iLike]: `%${searchTerm}%` } }
        ]
      },
      attributes: ['id', 'name', 'phone', 'email', 'avatar_url'],
      limit: 15
    });

    // Final safety check: ensure all returned users have a valid name string
    const sanitizedUsers = users.map(u => {
      const plain = u.toJSON();
      if (!plain.name || plain.name.trim() === '') {
        plain.name = "Member"; // Fallback for legacy corrupted data
      }
      return plain;
    });

    res.json(sanitizedUsers);
  } catch (err) {
    console.error("Search API Error:", err);
    res.status(500).json({ error: "Search failed. Please try again." });
  }
};
