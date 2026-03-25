const { Tour, User, JoinRequest, Expense, ExpenseSplit, ExpensePayer, Settlement, TourMember, sequelize } = require('../models');
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
            include: [
              { 
                model: User,
                through: { attributes: ['status', 'joined_at', 'removed_at', 'meal_count'] }
              }
            ]
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

    // Check if already member (including removed ones)
    const existingConnection = await TourMember.findOne({
      where: { tour_id: tour.id, user_id: user_id },
      transaction: t
    });

    if (existingConnection && existingConnection.status === 'active') {
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

    // Join or Reactivate
    if (existingConnection) {
      await existingConnection.update({ 
        status: 'active', 
        removed_at: null,
        joined_at: new Date() // Refresh join date? Or keep original? Let's refresh.
      }, { transaction: t });
    } else {
      await tour.addUser(user, { transaction: t });
    }
    
    // Commit the transaction
    await t.commit();
    
    // Fetch the complete tour with all members, expenses, and settlements to return
    const completeTour = await Tour.findByPk(tour.id, {
      include: [
        { 
          model: User,
          through: { attributes: ['status', 'joined_at', 'removed_at', 'meal_count'] }
        },
        { 
          model: Expense,
          include: [ExpenseSplit, ExpensePayer]
        },
        { model: Settlement },
        { model: ProgramIncome }
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

exports.deleteTour = async (req, res) => {
  try {
    const { tourId, userId } = req.body;
    const tour = await Tour.findByPk(tourId);
    
    if (!tour) return res.status(404).json({ error: 'Tour not found' });
    
    // Only creator can delete for everyone
    if (tour.created_by !== userId) {
      return res.status(403).json({ error: 'Only the creator can delete this tour' });
    }

    await tour.destroy();
    res.json({ message: 'Tour deleted successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.removeMember = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { tourId, userId } = req.body;
    
    const connection = await TourMember.findOne({
      where: { tour_id: tourId, user_id: userId },
      transaction: t
    });

    if (!connection) {
      await t.rollback();
      return res.status(404).json({ error: 'Member not found in this tour' });
    }

    if (connection.status === 'removed') {
      await t.rollback();
      return res.status(400).json({ error: 'Member is already removed' });
    }

    // Soft remove
    await connection.update({ 
      status: 'removed', 
      removed_at: new Date() 
    }, { transaction: t });

    await t.commit();
    res.json({ message: 'Member removed successfully' });
  } catch (err) {
    if (t) await t.rollback();
    res.status(500).json({ error: err.message });
  }
};


exports.addMember = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { tourId } = req.params;
    const { userId } = req.body;
    
    const tour = await Tour.findByPk(tourId, { transaction: t });
    const user = await User.findByPk(userId, { transaction: t });
    
    if (!tour || !user) {
      await t.rollback();
      return res.status(404).json({ error: 'Tour or User not found' });
    }

    const existingMember = await TourMember.findOne({
      where: { tour_id: tourId, user_id: userId },
      transaction: t
    });

    if (existingMember) {
      if (existingMember.status === 'active') {
        await t.rollback();
        return res.status(400).json({ error: 'Already a member' });
      } else {
        await existingMember.update({ status: 'active', removed_at: null }, { transaction: t });
      }
    } else {
      await tour.addUser(user, { transaction: t });
    }

    await t.commit();
    res.json({ message: 'Member added successfully' });
  } catch (err) {
    if (t) await t.rollback();
    res.status(500).json({ error: err.message });
  }
};

exports.updateMemberRole = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { tourId, userId } = req.params;
    const { role } = req.body; // 'admin', 'editor', 'viewer'
    
    // Authorization check could be added here (e.g., only admin can change)
    // req.user has the current logged in user.
    
    const member = await TourMember.findOne({
      where: { tour_id: tourId, user_id: userId },
      transaction: t
    });

    if (!member) {
      await t.rollback();
      return res.status(404).json({ error: 'Member not found in this tour' });
    }

    await member.update({ role }, { transaction: t });
    await t.commit();
    res.json({ message: 'Role updated successfully', role });
  } catch (err) {
    if (t) await t.rollback();
    res.status(500).json({ error: err.message });
  }
};
