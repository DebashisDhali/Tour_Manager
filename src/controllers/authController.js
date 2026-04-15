const { User } = require('../models');
const { Op } = require('sequelize');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'super-secret-key-123';

exports.register = async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;

    // Construct search conditions dynamically
    const conditions = [];
    if (email) conditions.push({ email });
    if (phone && phone.trim() !== '') conditions.push({ phone });

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
      name,
      email,
      phone: (phone && phone.trim() !== '') ? phone : null,
      password: hashedPassword,
      is_registered: true
    });

    const token = jwt.sign({ id: user.id }, JWT_SECRET, { expiresIn: '30d' });

    res.status(201).json({ user, token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};


exports.login = async (req, res) => {
  try {
    const { email, phone, password } = req.body;

    const user = await User.findOne({ 
      where: { 
        [Op.or]: [
          email ? { email } : null,
          phone ? { phone } : null
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

    const token = jwt.sign({ id: user.id }, JWT_SECRET, { expiresIn: '30d' });

    res.json({ user, token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getMe = async (req, res) => {
  try {
    const user = await User.findByPk(req.user.id);
    res.json(user);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
