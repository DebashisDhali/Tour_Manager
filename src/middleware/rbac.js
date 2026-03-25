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

      const member = await TourMember.findOne({
        where: { tour_id: tId, user_id: req.user.id, status: 'active' }
      });

      if (!member) {
        return res.status(403).json({ error: 'You are not a member of this tour' });
      }

      if (roles && !roles.includes(member.role)) {
        return res.status(403).json({ error: `Permission denied. Requires one of: ${roles.join(', ')}. Your role: ${member.role}` });
      }

      req.member = member;
      req.currentTourId = tId;
      next();
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  };
};
