const { User } = require('../models');
const { Op } = require('sequelize');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

function sanitizeUser(user) {
  if (!user) return null;
  const plain = typeof user.toJSON === 'function' ? user.toJSON() : user;
  const { password, ...safe } = plain;
  return safe;
}

function issueToken(userId) {
  if (!JWT_SECRET) {
    throw new Error('JWT_SECRET is not configured');
  }
  return jwt.sign({ id: userId }, JWT_SECRET, {
    expiresIn: '30d',
    algorithm: 'HS256',
    issuer: 'tour-expense-backend',
    audience: 'tour-expense-client'
  });
}

exports.register = async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;

    if (!name || name.trim().length < 2) {
      return res.status(400).json({ error: 'Name must be at least 2 characters' });
    }
    if (!password || password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }

    const normalizedEmail = email ? email.trim().toLowerCase() : null;
    const normalizedPhone = phone && phone.trim() !== '' ? phone.trim() : null;

    // Construct search conditions dynamically
    const conditions = [];
    if (normalizedEmail) conditions.push({ email: normalizedEmail });
    if (normalizedPhone) conditions.push({ phone: normalizedPhone });

    if (conditions.length > 0) {
      const existingUser = await User.findOne({ 
        where: { [Op.or]: conditions } 
      });

      if (existingUser) {
        return res.status(400).json({ error: 'User with this email or phone already exists' });
      }
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await User.create({
      name: name.trim(),
      email: normalizedEmail,
      phone: normalizedPhone,
      password: hashedPassword,
      is_registered: true
    });

    const token = issueToken(user.id);

    res.status(201).json({ user: sanitizeUser(user), token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};


exports.login = async (req, res) => {
  try {
    const { email, phone, password } = req.body;

    const normalizedEmail = email ? email.trim().toLowerCase() : null;
    const normalizedPhone = phone ? phone.trim() : null;

    if ((!normalizedEmail && !normalizedPhone) || !password) {
      return res.status(400).json({ error: 'Email or phone and password are required' });
    }

    const user = await User.findOne({ 
      where: { 
        [Op.or]: [
          normalizedEmail ? { email: normalizedEmail } : null,
          normalizedPhone ? { phone: normalizedPhone } : null
        ].filter(Boolean)
      } 
    });

    if (!user || !user.password) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = issueToken(user.id);

    res.json({ user: sanitizeUser(user), token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getMe = async (req, res) => {
  try {
    const user = await User.findByPk(req.user.id, {
      attributes: { exclude: ['password'] }
    });
    res.json(sanitizeUser(user));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
