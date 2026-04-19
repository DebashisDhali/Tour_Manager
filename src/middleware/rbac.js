const { TourMember, Expense, Settlement, ProgramIncome } = require('../models');

exports.checkTourAccess = (roles) => {
  return async (req, res, next) => {
    try {
      const { tourId, tour_id, id } = { ...req.params, ...req.body, ...req.query };
      let tId = tourId || tour_id;

      // If we only have 'id' (e.g. for /expenses/:id), find the tourId first
      if (!tId && id) {
        if (req.baseUrl.includes('expenses')) {
          const exp = await Expense.findByPk(id);
          tId = exp?.tour_id;
        } else if (req.baseUrl.includes('settlements')) {
          const set = await Settlement.findByPk(id);
          tId = set?.tour_id;
        } else if (req.baseUrl.includes('incomes')) {
          const inc = await ProgramIncome.findByPk(id);
          tId = inc?.tour_id;
        } else if (req.baseUrl.includes('tours')) {
          tId = id;
        }
      }

      if (!tId) {
        return res.status(400).json({ error: 'Tour context not found' });
      }

      // Normalize IDs to handle case sensitivity issues
      const normalizedTourId = tId?.toString().toLowerCase() || '';
      const normalizedUserId = req.user.id?.toString().toLowerCase() || '';
      
      if (!normalizedTourId || !normalizedUserId) {
        return res.status(400).json({ error: 'Invalid tour or user context' });
      }

      const member = await TourMember.findOne({
        where: { tour_id: normalizedTourId, user_id: normalizedUserId, status: 'active' }
      });

      if (!member) {
        return res.status(403).json({ error: 'You are not a member of this tour' });
      }

      if (roles && !roles.includes(member.role)) {
        return res.status(403).json({ error: `Permission denied. Requires one of: ${roles.join(', ')}. Your role: ${member.role}` });
      }

      req.member = member;
      req.currentTourId = normalizedTourId;
      next();
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  };
};
