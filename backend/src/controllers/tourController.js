const { Tour, User, JoinRequest, Expense, ExpenseSplit, ExpensePayer, Settlement, sequelize } = require('../models');
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
  const t = await sequelize.transaction();
  try {
    const { invite_code, user_id, user_name } = req.body;
    console.log(`Join attempt: Code=${invite_code}, User=${user_name} (${user_id})`);
    
    // Find tour with current members
    const tour = await Tour.findOne({ 
      where: { invite_code },
      transaction: t
    });
    
    if (!tour) {
      console.log(`Join failed: Invite code ${invite_code} not found.`);
      await t.rollback();
      return res.status(404).json({ error: 'Invalid invite code' });
    }

    // Check if already member
    const isMember = await tour.hasUser(user_id, { transaction: t });
    if (isMember) {
      await t.rollback();
      return res.status(400).json({ error: 'You are already a member' });
    }

    // Ensure User exists in Backend
    let user = await User.findByPk(user_id, { transaction: t });
    if (!user) {
      user = await User.create({ 
        id: user_id, 
        name: user_name,
        email: req.body.email,
        avatar_url: req.body.avatar_url,
        purpose: req.body.purpose
      }, { transaction: t });
    } else {
      // Update user details if changed
      await user.update({ 
        name: user_name,
        email: req.body.email || user.email,
        avatar_url: req.body.avatar_url || user.avatar_url,
        purpose: req.body.purpose || user.purpose
      }, { transaction: t });
    }

    // Join directly
    await tour.addUser(user, { transaction: t });
    
    // Commit the transaction
    await t.commit();
    
    // Fetch the complete tour with all members, expenses, and settlements to return
    const completeTour = await Tour.findByPk(tour.id, {
      include: [
        { model: User }, // Members
        { 
          model: Expense,
          include: [ExpenseSplit, ExpensePayer]
        },
        { model: Settlement }
      ]
    });
    console.log(`Join successful for ${user_name} to Tour ${completeTour.name}`);
    
    res.json({ 
      message: 'Joined successfully!', 
      tour_id: completeTour.id,
      tour_name: completeTour.name,
      tour: completeTour // Return full tour data
    });
  } catch (err) {
    await t.rollback();
    res.status(500).json({ error: err.message });
  }
};


