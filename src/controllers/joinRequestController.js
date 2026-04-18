const { JoinRequest, Tour, User, TourMember, sequelize } = require('../models');

exports.createJoinRequest = async (req, res) => {
  try {
    const tourId = req.params.tourId || req.body.tourId;

    if (!tourId) {
      return res.status(400).json({ error: 'tourId is required' });
    }

    const tour = await Tour.findByPk(tourId);
    if (!tour) return res.status(404).json({ error: 'Tour not found' });

    // Check if already a member
    const existingMember = await TourMember.findOne({ where: { tour_id: tourId, user_id: req.user.id } });
    if (existingMember && existingMember.status === 'active') {
      return res.status(400).json({ error: 'You are already a member of this tour' });
    }

    // Check if already has a pending request
    const existingRequest = await JoinRequest.findOne({ 
      where: { tour_id: tourId, user_id: req.user.id, status: 'pending' } 
    });
    if (existingRequest) {
      return res.status(400).json({ error: 'You already have a pending request for this tour' });
    }

    const joinRequest = await JoinRequest.create({
      tour_id: tourId,
      user_id: req.user.id,
      user_name: req.user.name,
      status: 'pending'
    });

    res.status(201).json(joinRequest);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getTourRequests = async (req, res) => {
  try {
    const { tourId } = req.params;
    const requests = await JoinRequest.findAll({ 
      where: { tour_id: tourId, status: 'pending' } 
    });
    res.json(requests);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.handleJoinRequest = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { requestId } = req.params;
    const { status, role } = req.body; // 'approved' or 'rejected'
    const normalizedStatus = (status || '').toLowerCase();
    const normalizedRole = (role || 'viewer').toLowerCase();

    if (!['approved', 'rejected'].includes(normalizedStatus)) {
      await t.rollback();
      return res.status(400).json({ error: 'status must be approved or rejected' });
    }

    if (!['admin', 'editor', 'viewer'].includes(normalizedRole)) {
      await t.rollback();
      return res.status(400).json({ error: 'role must be admin, editor, or viewer' });
    }

    const request = await JoinRequest.findByPk(requestId, { transaction: t });
    if (!request) {
      await t.rollback();
      return res.status(404).json({ error: 'Request not found' });
    }

    if (normalizedStatus === 'approved') {
      const tour = await Tour.findByPk(request.tour_id, { transaction: t });
      const user = await User.findByPk(request.user_id, { transaction: t });

      if (!tour || !user) {
         await t.rollback();
         return res.status(404).json({ error: 'Tour or User no longer exists' });
      }

      // Add as member
      await TourMember.upsert({
        tour_id: request.tour_id,
        user_id: request.user_id,
        role: normalizedRole,
        status: 'active',
        joined_at: new Date()
      }, { transaction: t });

      await request.update({ status: 'approved' }, { transaction: t });
    } else {
      await request.update({ status: 'rejected' }, { transaction: t });
    }

    await t.commit();
    res.json({ message: `Request ${normalizedStatus} successfully` });
  } catch (err) {
    if (t) await t.rollback();
    res.status(500).json({ error: err.message });
  }
};
