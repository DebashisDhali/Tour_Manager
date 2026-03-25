const { ProgramIncome, Tour, User } = require('../models');

exports.createProgramIncome = async (req, res) => {
  try {
    const { id, tourId, amount, source, description, collectedBy, date } = req.body;
    
    // Check if tour exists
    const tour = await Tour.findByPk(tourId);
    if (!tour) return res.status(404).json({ error: 'Tour not found' });

    const income = await ProgramIncome.create({
      id,
      tour_id: tourId,
      amount,
      source,
      description,
      collected_by: collectedBy,
      date
    });

    res.status(201).json(income);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.deleteProgramIncome = async (req, res) => {
  try {
    const { id } = req.body;
    const income = await ProgramIncome.findByPk(id);
    if (!income) return res.status(404).json({ error: 'Income not found' });

    await income.destroy();
    res.json({ message: 'Income deleted successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getIncomesByTour = async (req, res) => {
  try {
    const { tourId } = req.params;
    const incomes = await ProgramIncome.findAll({ 
      where: { tour_id: tourId },
      include: [{ model: User, as: 'collector' }] 
    });
    res.json(incomes);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
