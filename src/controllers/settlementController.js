const { Settlement, sequelize } = require('../models');

exports.createSettlement = async (req, res) => {
  try {
    const { id, tour_id, from_id, to_id, amount, date } = req.body;
    const settlement = await Settlement.create({
      id: (id || uuidv4()).toLowerCase(),
      tour_id: tour_id.toLowerCase(),
      from_id: from_id.toLowerCase(),
      to_id: to_id.toLowerCase(),
      amount,
      date: date || new Date()
    });
    res.status(201).json(settlement);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getSettlementsByTour = async (req, res) => {
  try {
    const settlements = await Settlement.findAll({
      where: { tour_id: req.params.tourId },
      include: ['sender', 'receiver']
    });
    res.json(settlements);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.deleteSettlement = async (req, res) => {
    try {
        const deleted = await Settlement.destroy({ where: { id: req.params.id } });
        if (!deleted) return res.status(404).json({ error: 'Settlement not found' });
        res.json({ message: 'Settlement deleted' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};
