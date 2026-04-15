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
    // Normalize phone search: remove all non-digits for a deep search
    const digitsOnly = searchTerm.replace(/\D/g, '');

    const searchConditions = [
      { name: { [Op.iLike]: `%${searchTerm}%` } },
      { email: { [Op.iLike]: `%${searchTerm}%` } },
      { phone: { [Op.iLike]: `%${searchTerm}%` } }
    ];

    // If query contains digits, search for variations
    if (digitsOnly.length >= 6) {
        // Match last digits (to handle country code issues)
        searchConditions.push({ phone: { [Op.iLike]: `%${digitsOnly}%` } });
        
        // Handle leading zero variations for BD numbers
        if (digitsOnly.startsWith('0')) {
            searchConditions.push({ phone: { [Op.iLike]: `%${digitsOnly.substring(1)}%` } });
        } else {
            searchConditions.push({ phone: { [Op.iLike]: `%0${digitsOnly}%` } });
        }
    }

    const users = await User.findAll({
      where: {
        [Op.or]: searchConditions
      },
      attributes: ['id', 'name', 'phone', 'email', 'avatar_url', 'is_registered'],
      order: [['is_registered', 'DESC'], ['name', 'ASC']],
      limit: 20
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
    console.error("Critical Search API Error:", err);
    res.status(500).json({ error: "Search system experience an issue. We are investigating." });
  }
};
