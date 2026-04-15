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
    const searchConditions = [
      { name: { [Op.iLike]: `%${searchTerm}%` } },
      { email: { [Op.iLike]: `%${searchTerm}%` } }
    ];

    // Standard phone match
    searchConditions.push({ phone: { [Op.iLike]: `%${searchTerm}%` } });

    // Intelligent Phone Matching: 
    // If it looks like a BD mobile number (starts with 01)
    if (/^01[3-9]\d{8}$/.test(searchTerm)) {
      const withoutZero = searchTerm.substring(1); // e.g. 1757445693
      searchConditions.push({ phone: { [Op.iLike]: `%${withoutZero}%` } });
    } else if (/^[3-9]\d{8}$/.test(searchTerm)) {
      // If user forgot leading 0
      searchConditions.push({ phone: { [Op.iLike]: `%0${searchTerm}%` } });
    }

    const users = await User.findAll({
      where: {
        [Op.or]: searchConditions
      },
      attributes: ['id', 'name', 'phone', 'email', 'avatar_url'],
      limit: 15
    });

    const sanitizedUsers = users.map(u => {
      const plain = u.toJSON();
      if (!plain.name || plain.name.trim() === '') {
        plain.name = "Member";
      }
      return plain;
    });

    res.json(sanitizedUsers);
  } catch (err) {
    console.error("Search API Error:", err);
    res.status(500).json({ error: "Search failed. Please try again." });
  }
};
