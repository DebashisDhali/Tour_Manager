const { Tour, User, JoinRequest, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, sequelize } = require('../models');
const { v4: uuidv4 } = require('uuid');
const { Op } = require('sequelize');

const INVITE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function generateInviteCode() {
  return Array.from({ length: 6 }, () => INVITE_CHARS[Math.floor(Math.random() * INVITE_CHARS.length)]).join('');
}

function parsePageNumber(raw, fallback) {
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

exports.createTour = async (req, res) => {
  try {
    const { id, name, start_date, end_date } = req.body;
    const created_by = req.user.id;
    const now = new Date();

    if (!name || !name.toString().trim()) {
      return res.status(400).json({ error: 'Tour name is required' });
    }

    const invite_code = req.body.invite_code || generateInviteCode();
    const tour = await Tour.create({ 
      id: (id || uuidv4()).toLowerCase(), 
      name: name.toString().trim(), 
      created_by: created_by.toLowerCase(), 
      invite_code,
      start_date,
      end_date,
      created_at: now,
      updated_at: now
    });

    // Add creator to members explicitly so timestamp columns are always set.
    const user = await User.findByPk(created_by);
    if (user) {
      await TourMember.upsert({
        tour_id: tour.id.toLowerCase(),
        user_id: user.id.toLowerCase(),
        role: 'admin',
        status: 'active',
        joined_at: now,
        created_at: now,
        updated_at: now,
      });
    }

    res.status(201).json(tour);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};


exports.getAllTours = async (req, res) => {
  try {
    const page = parsePageNumber(req.query.page, 1);
    const limit = Math.min(parsePageNumber(req.query.limit, 30), 100);
    const offset = (page - 1) * limit;

    const tours = await Tour.findAll({
      include: [
        {
          model: TourMember,
          required: true,
          where: {
            user_id: req.user.id,
            status: 'active'
          },
          attributes: ['role', 'status', 'joined_at']
        }
      ],
      limit,
      offset
    });

    // Light caching hint for short-lived list reads.
    res.set('Cache-Control', 'private, max-age=30');
    res.json(tours);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getTourDetails = async (req, res) => {
    try {
        const normalizedTourId = req.params.id?.toString().toLowerCase() || '';
        const tour = await Tour.findByPk(normalizedTourId, {
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
exports.findTourByCode = async (req, res) => {
  const code = req.params.code ? req.params.code.replace(/[^a-zA-Z0-9]/g, '').trim().toUpperCase() : '';
  console.log(`Searching for tour with code: "${code}"`);

  if (!code || code.length < 4 || code.length > 10) {
    return res.status(400).json({ error: 'Invalid code format' });
  }

  try {
    const tour = await Tour.findOne({ 
      where: {
        invite_code: code
      },
      attributes: ['id', 'name', 'purpose', 'created_by'] 
    });
    if (!tour) return res.status(404).json({ error: 'Tour not found' });
    res.status(200).json(tour);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.regenerateInviteCode = async (req, res) => {
  const { tourId } = req.params;
  if (!tourId) {
    return res.status(400).json({ error: 'tourId is required' });
  }

  const t = await sequelize.transaction();
  try {
    const normalizedTourId = tourId?.toString().toLowerCase() || '';
    const tour = await Tour.findByPk(normalizedTourId, { transaction: t });
    if (!tour) {
      await t.rollback();
      return res.status(404).json({ error: 'Tour not found' });
    }

    let inviteCode = null;
    for (let i = 0; i < 8; i++) {
      const candidate = generateInviteCode();
      const existing = await Tour.findOne({
        where: { invite_code: candidate, id: { [Op.ne]: tourId } },
        transaction: t
      });
      if (!existing) {
        inviteCode = candidate;
        break;
      }
    }

    if (!inviteCode) {
      await t.rollback();
      return res.status(500).json({ error: 'Failed to generate unique invite code. Please try again.' });
    }

    await tour.update({ invite_code: inviteCode }, { transaction: t });
    await t.commit();

    return res.status(200).json({
      tourId: tour.id,
      inviteCode,
      message: 'Invite code generated and published to cloud'
    });
  } catch (err) {
    if (t) await t.rollback();
    return res.status(500).json({ error: err.message });
  }
};

exports.joinTour = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    let { invite_code } = req.body;
    const user_id = req.user.id;
    const user_name = req.user.name || req.body.user_name || 'Member';
    invite_code = invite_code ? invite_code.replace(/[^a-zA-Z0-9]/g, '').trim().toUpperCase() : '';

    if (!invite_code) {
      await t.rollback();
      return res.status(400).json({ error: 'Invite code is required' });
    }

    console.log(`Join attempt: Code=${invite_code}, User=${user_name} (${user_id})`);
    
    // Find tour with current members
    const tour = await Tour.findOne({ 
      where: {
        invite_code: invite_code
      },
      transaction: t
    });
    
    if (!tour) {
      console.log(`Join failed: Invite code ${invite_code} not found.`);
      await t.rollback();
      return res.status(404).json({ error: 'Invalid invite code' });
    }

    // Check if already member (including removed ones)
    const existingConnection = await TourMember.findOne({
      where: { tour_id: tour.id.toLowerCase(), user_id: user_id.toLowerCase() },
      transaction: t
    });

    if (existingConnection && existingConnection.status === 'active') {
      await t.rollback();
      return res.status(400).json({ error: 'You are already a member' });
    }

    // Ensure User exists in Backend
    let user = await User.findByPk(user_id.toLowerCase(), { transaction: t });
    if (!user) {
      user = await User.create({ 
        id: user_id.toLowerCase(), 
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
        joined_at: new Date(),
        role: 'viewer' // Reset to viewer when re-joining via code
      }, { transaction: t });
    } else {
      const now = new Date();
      await TourMember.upsert({
        tour_id: tour.id.toLowerCase(),
        user_id: user.id.toLowerCase(),
        role: 'viewer',
        status: 'active',
        joined_at: now,
        created_at: now,
        updated_at: now,
      }, { transaction: t });
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
    const { tourId } = req.body;
    const tour = await Tour.findByPk(tourId);
    
    if (!tour) return res.status(404).json({ error: 'Tour not found' });
    
    // Only creator can delete for everyone
    if (tour.created_by !== req.user.id) {
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
    
    // Normalize IDs for case sensitivity
    const normalizedTourId = tourId?.toString().toLowerCase() || '';
    const normalizedUserId = userId?.toString().toLowerCase() || '';

    const connection = await TourMember.findOne({
      where: { tour_id: normalizedTourId, user_id: normalizedUserId },
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

    // Normalize IDs to handle case sensitivity - backend stores everything lowercase
    const normalizedTourId = tourId?.toString().toLowerCase() || '';
    const normalizedUserId = userId?.toString().toLowerCase() || '';
    const requesterId = req.user?.id?.toString().toLowerCase() || '';
    
    if (!normalizedTourId || !normalizedUserId || !requesterId) {
      await t.rollback();
      return res.status(400).json({ error: 'Invalid tour or user ID' });
    }
    
    let tour = await Tour.findByPk(normalizedTourId, { transaction: t });
    if (!tour) {
      tour = await Tour.findOne({
        where: { id: { [Op.iLike]: normalizedTourId } },
        transaction: t,
      });
    }

    let user = await User.findByPk(normalizedUserId, { transaction: t });
    if (!user) {
      user = await User.findOne({
        where: { id: { [Op.iLike]: normalizedUserId } },
        transaction: t,
      });
    }

    if (!tour) {
      await t.rollback();
      return res.status(404).json({ error: 'Tour not found' });
    }
    if (!user) {
      await t.rollback();
      return res.status(404).json({ error: 'User not found' });
    }

    // Authorization for inviter: active admin/editor member OR owner (self-heal owner membership if missing)
    let requesterMember = await TourMember.findOne({
      where: { tour_id: normalizedTourId, user_id: requesterId, status: 'active' },
      transaction: t,
    });

    const isOwner =
      tour.created_by &&
      tour.created_by.toString().toLowerCase() === requesterId;

    if (!requesterMember && isOwner) {
      const now = new Date();
      await TourMember.upsert(
        {
          tour_id: normalizedTourId,
          user_id: requesterId,
          status: 'active',
          role: 'admin',
          removed_at: null,
          joined_at: now,
          created_at: now,
          updated_at: now,
        },
        { transaction: t }
      );

      requesterMember = await TourMember.findOne({
        where: { tour_id: normalizedTourId, user_id: requesterId, status: 'active' },
        transaction: t,
      });
    }

    const inviterRole = requesterMember?.role?.toString().toLowerCase() || '';
    if (!requesterMember || !['admin', 'editor'].includes(inviterRole)) {
      await t.rollback();
      return res.status(403).json({ error: 'You are not a member of this tour' });
    }

    const existingMember = await TourMember.findOne({
      where: { tour_id: normalizedTourId, user_id: normalizedUserId },
      transaction: t
    });

    if (existingMember) {
      if (existingMember.status === 'active') {
        await t.rollback();
        return res.status(400).json({ error: 'Already a member' });
      } else if (existingMember.status === 'pending') {
        await t.rollback();
        return res.status(400).json({ error: 'Invitation already pending' });
      } else {
        await existingMember.update(
          { status: 'pending', removed_at: null, role: 'viewer' },
          { transaction: t }
        );
      }
    } else {
      const now = new Date();
      await TourMember.create(
        {
          tour_id: normalizedTourId,
          user_id: normalizedUserId,
          role: 'viewer',
          status: 'pending',
          joined_at: now,
          created_at: now,
          updated_at: now,
        },
        { transaction: t }
      );
    }

    await t.commit();
    res.json({ message: 'Invitation sent successfully' });
  } catch (err) {
    if (t) await t.rollback();
    res.status(500).json({ error: err.message });
  }
};

exports.getMyInvitations = async (req, res) => {
  try {
    const normalizedUserId = req.user?.id?.toString().toLowerCase() || '';
    const invitations = await TourMember.findAll({
      where: { user_id: normalizedUserId, status: 'pending' },
      include: [{ model: Tour, attributes: ['id', 'name', 'purpose', 'created_by'] }]
    });

    const payload = invitations.map((inv) => ({
      tourId: inv.tour_id,
      role: inv.role,
      status: inv.status,
      joinedAt: inv.joined_at,
      tour: inv.Tour,
    }));

    return res.json(payload);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
};

exports.respondToInvitation = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { tourId } = req.params;
    const action = (req.body.action || '').toLowerCase();

    if (!['accept', 'reject'].includes(action)) {
      await t.rollback();
      return res.status(400).json({ error: 'action must be accept or reject' });
    }

    // Normalize IDs for case sensitivity
    const normalizedTourId = tourId?.toString().toLowerCase() || '';
    const normalizedUserId = req.user.id?.toString().toLowerCase() || '';

    const member = await TourMember.findOne({
      where: {
        tour_id: normalizedTourId,
        user_id: normalizedUserId,
        status: 'pending'
      },
      transaction: t
    });

    if (!member) {
      await t.rollback();
      return res.status(404).json({ error: 'Pending invitation not found' });
    }

    if (action === 'accept') {
      await member.update(
        {
          status: 'active',
          removed_at: null,
          joined_at: new Date()
        },
        { transaction: t }
      );
    } else {
      await member.update(
        {
          status: 'removed',
          removed_at: new Date()
        },
        { transaction: t }
      );
    }

    await t.commit();
    return res.json({ message: `Invitation ${action}ed successfully` });
  } catch (err) {
    if (t) await t.rollback();
    return res.status(500).json({ error: err.message });
  }
};

exports.updateMemberRole = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { tourId, userId } = req.params;
    const { role } = req.body; // 'admin', 'editor', 'viewer'
    
    // Authorization check could be added here (e.g., only admin can change)
    // req.user has the current logged in user.
    
    // Normalize IDs for case sensitivity
    const normalizedTourId = tourId?.toString().toLowerCase() || '';
    const normalizedUserId = userId?.toString().toLowerCase() || '';

    const member = await TourMember.findOne({
      where: { tour_id: normalizedTourId, user_id: normalizedUserId },
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

exports.retroactiveSplit = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { tourId, userId: rawUserId } = req.params;
    const userId = rawUserId.toLowerCase();

    // 1. Get ALL active members for this tour
    const activeMembers = await TourMember.findAll({
      where: { tour_id: tourId.toLowerCase(), status: 'active', is_deleted: false },
      transaction: t
    });

    if (activeMembers.length === 0) {
      await t.rollback();
      return res.status(404).json({ error: 'No active members found in this tour' });
    }

    const participants = activeMembers.map(m => m.user_id.toLowerCase());
    
    // Check if the requested user is actually one of the active members
    if (!participants.includes(userId)) {
      await t.rollback();
      return res.status(403).json({ error: 'Selected user is not an active member of this tour' });
    }

    // 2. Get all expenses for this tour
    const expenses = await Expense.findAll({
      where: { tour_id: tourId.toLowerCase(), is_deleted: false },
      transaction: t
    });

    for (const expense of expenses) {
      const totalAmount = parseFloat(expense.amount);
      const participantCount = participants.length;
      
      // Calculate precise equal share
      const equalAmount = Math.floor((totalAmount / participantCount) * 100) / 100;
      const remainder = Math.round((totalAmount - (equalAmount * participantCount)) * 100) / 100;

      // 3. Delete ALL existing splits for this expense to do a clean re-split
      // We only do this if the expense doesn't have custom splits logic 
      // (For now, we assume all expenses in this flow are equal-split)
      await ExpenseSplit.destroy({
        where: { expense_id: expense.id },
        transaction: t
      });

      // 4. Create new splits for EVERY active participant
      const newSplits = [];
      for (let i = 0; i < participants.length; i++) {
        const splitAmount = i === 0 ? 
          Math.round((equalAmount + remainder) * 100) / 100 : 
          equalAmount;
          
        newSplits.push({
          id: uuidv4().toLowerCase(),
          expense_id: expense.id,
          user_id: participants[i],
          amount: splitAmount
        });
      }

      await ExpenseSplit.bulkCreate(newSplits, { transaction: t });
      
      // Update expense synced_at to trigger re-sync for everyone
      await expense.update({ synced_at: new Date() }, { transaction: t });
    }

    await t.commit();
    res.json({ message: `Success: All past expenses re-split among ${activeMembers.length} active members.` });
  } catch (err) {
    if (t) await t.rollback();
    res.status(500).json({ error: err.message });
  }
};

exports.checkDbSchema = async (req, res) => {
  try {
    const rawSchema = await sequelize.query(
      `SELECT column_name, data_type, is_nullable, column_default 
       FROM information_schema.columns 
       WHERE table_name IN ('Tours', 'Users', 'TourMembers', 'tours', 'users', 'tourmembers')`,
      { type: sequelize.QueryTypes.SELECT }
    );
    res.json({
      status: 'success',
      node_env: process.env.NODE_ENV,
      rawSchema,
      models: {
        Tour: Object.keys(Tour.rawAttributes),
        TourMember: Object.keys(TourMember.rawAttributes),
        User: Object.keys(User.rawAttributes)
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message, status: 'failed' });
  }
};
