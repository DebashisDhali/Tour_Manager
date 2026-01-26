const { Tour, User, JoinRequest, sequelize } = require('../models');
const { v4: uuidv4 } = require('uuid');

exports.createTour = async (req, res) => {
  try {
    const { id, name, created_by, start_date, end_date } = req.body;
    
    // Generate simple 6-char invite code
    const invite_code = Math.random().toString(36).substring(2, 8).toUpperCase();

    const tour = await Tour.create({ 
      id: id || uuidv4(), 
      name, 
      created_by, 
      invite_code,
      start_date,
      end_date
    });

    // Add creator to members
    const user = await User.findByPk(created_by);
    if (user) {
      await tour.addUser(user);
    }

    res.status(201).json(tour);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};


exports.getAllTours = async (req, res) => {
  try {
    const tours = await Tour.findAll();
    res.json(tours);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getTourDetails = async (req, res) => {
    try {
        const tour = await Tour.findByPk(req.params.id, {
            include: [{ model: User }]
        });
        if (!tour) return res.status(404).json({ message: 'Tour not found' });
        res.json(tour);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};

// Invitation Logic - Joins Immediately (No Approval Required)
exports.joinTour = async (req, res) => {
  try {
    const { invite_code, user_id, user_name } = req.body;
    const tour = await Tour.findOne({ where: { invite_code } });
    if (!tour) return res.status(404).json({ error: 'Invalid invite code' });

    // Check if already member
    const isMember = await tour.hasUser(user_id);
    if (isMember) return res.status(400).json({ error: 'You are already a member' });

    // Ensure User exists in Backend
    let user = await User.findByPk(user_id);
    if (!user) {
      user = await User.create({ id: user_id, name: user_name });
    }

    // Join directly
    await tour.addUser(user);
    
    res.json({ 
      message: 'Joined successfully!', 
      tour_id: tour.id,
      tour_name: tour.name 
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};


