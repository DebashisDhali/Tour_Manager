const jwt = require('jsonwebtoken');
const { User } = require('../models');

const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
  console.error('🔥 CRITICAL: JWT_SECRET is not configured. Refusing insecure startup.');
  process.exit(1);
}

module.exports = async (req, res, next) => {
  try {
    const authHeader = req.header('Authorization') || '';
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    const token = match ? match[1] : null;

    if (!token) {
      return res.status(401).json({ error: 'Auth token missing' });
    }

    const decoded = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] });
    const user = await User.findByPk(decoded.id, {
      attributes: { exclude: ['password'] }
    });

    if (!user) {
      throw new Error();
    }

    // Ensure ID is normalized to lowercase for consistent lookups throughout the app
    user.id = user.id.toLowerCase();

    req.token = token;
    req.user = user;
    next();
  } catch (err) {
    res.status(401).json({ error: 'Please authenticate' });
  }
};
