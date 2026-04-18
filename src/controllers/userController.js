const { User } = require('../models');
const { Op } = require('sequelize');

function parsePageNumber(raw, fallback) {
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function sanitizeUser(user) {
  if (!user) return null;
  const plain = typeof user.toJSON === 'function' ? user.toJSON() : user;
  const { password, ...safe } = plain;
  return safe;
}

exports.createUser = async (req, res) => {
  try {
    const { id, name, phone } = req.body;
    if (!name || !name.toString().trim()) {
      return res.status(400).json({ error: 'name is required' });
    }

    // Insert or update to support sync
    const [user] = await User.upsert({
        id,
        name: name.toString().trim(),
        phone,
        is_registered: true
    });

    res.status(201).json(sanitizeUser(user));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getAllUsers = async (req, res) => {
  try {
    const page = parsePageNumber(req.query.page, 1);
    const limit = Math.min(parsePageNumber(req.query.limit, 50), 100);
    const offset = (page - 1) * limit;

    const users = await User.findAll({
      attributes: ['id', 'name', 'phone', 'email', 'avatar_url', 'purpose', 'is_registered', 'created_at', 'updated_at'],
      order: [['updated_at', 'DESC']],
      limit,
      offset
    });

    res.json(users.map(sanitizeUser));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.searchUsers = async (req, res) => {
  try {
    const { query } = req.query;
    if (!query || query.trim().length === 0) return res.json([]);

    const searchTerm = query.trim();
    if (searchTerm.length < 2) return res.json([]);
    if (searchTerm.length > 80) {
      return res.status(400).json({ error: 'query too long' });
    }

    const limit = Math.min(parsePageNumber(req.query.limit, 20), 50);

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
      limit
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
