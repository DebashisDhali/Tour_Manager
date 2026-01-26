const { Expense, ExpenseSplit, sequelize } = require('../models');

exports.createExpense = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { id, tour_id, payer_id, amount, title, category, splits } = req.body;
    
    // Create Expense
    const expense = await Expense.create({
        id, tour_id, payer_id, amount, title, category, synced_at: new Date()
    }, { transaction: t });

    // Create Splits
    if (splits && splits.length > 0) {
        const splitRecords = splits.map(s => ({
            id: s.id, // Using client ID if provided
            expense_id: expense.id,
            user_id: s.user_id,
            amount: s.amount
        }));
        await ExpenseSplit.bulkCreate(splitRecords, { transaction: t });
    }

    await t.commit();
    res.status(201).json(expense);
  } catch (err) {
    await t.rollback();
    res.status(500).json({ error: err.message });
  }
};

exports.getExpensesByTour = async (req, res) => {
    try {
        const expenses = await Expense.findAll({
            where: { tour_id: req.params.tourId },
            include: ['payer', ExpenseSplit]
        });
        res.json(expenses);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};

exports.syncExpenses = async (req, res) => {
    // Basic implementation of bulk sync
    // In a real app, this would handle conflict resolution
    // Here we just accept what the client sends (Last Write Wins from client)
    const t = await sequelize.transaction();
    try {
        const { expenses } = req.body; // Array of expenses with splits
        
        for (const expData of expenses) {
             await Expense.upsert({
                 ...expData,
                 synced_at: new Date()
             }, { transaction: t });
             
             // Handle splits if included
             // ...
        }
        
        await t.commit();
        res.json({ status: 'synced', count: expenses.length });
    } catch (err) {
        await t.rollback();
        res.status(500).json({ error: err.message });
    }
};
