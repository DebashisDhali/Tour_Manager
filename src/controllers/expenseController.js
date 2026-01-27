const { Expense, ExpenseSplit, ExpensePayer, sequelize } = require('../models');

exports.createExpense = async (req, res) => {
  const t = await sequelize.transaction();
  try {
    const { id, tour_id, payer_id, amount, title, category, splits, payers } = req.body;
    
    const expense = await Expense.create({
        id, tour_id, payer_id, amount, title, category, synced_at: new Date()
    }, { transaction: t });

    if (splits && splits.length > 0) {
        const splitRecords = splits.map(s => ({
            id: s.id,
            expense_id: expense.id,
            user_id: s.user_id,
            amount: s.amount
        }));
        await ExpenseSplit.bulkCreate(splitRecords, { transaction: t });
    }

    if (payers && payers.length > 0) {
        const payerRecords = payers.map(p => ({
            id: p.id,
            expense_id: expense.id,
            user_id: p.user_id,
            amount: p.amount
        }));
        await ExpensePayer.bulkCreate(payerRecords, { transaction: t });
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
            include: ['payer', ExpenseSplit, ExpensePayer]
        });
        res.json(expenses);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};

exports.updateExpense = async (req, res) => {
    const t = await sequelize.transaction();
    try {
        const { amount, title, category, splits, payers } = req.body;
        const expenseId = req.params.id;

        const expense = await Expense.findByPk(expenseId);
        if (!expense) {
            await t.rollback();
            return res.status(404).json({ error: 'Expense not found' });
        }

        await expense.update({ amount, title, category, synced_at: new Date() }, { transaction: t });

        if (splits && splits.length > 0) {
            await ExpenseSplit.destroy({ where: { expense_id: expenseId }, transaction: t });
            const splitRecords = splits.map(s => ({
                id: s.id,
                expense_id: expenseId,
                user_id: s.user_id,
                amount: s.amount
            }));
            await ExpenseSplit.bulkCreate(splitRecords, { transaction: t });
        }

        if (payers && payers.length > 0) {
            await ExpensePayer.destroy({ where: { expense_id: expenseId }, transaction: t });
            const payerRecords = payers.map(p => ({
                id: p.id,
                expense_id: expenseId,
                user_id: p.user_id,
                amount: p.amount
            }));
            await ExpensePayer.bulkCreate(payerRecords, { transaction: t });
        }

        await t.commit();
        res.json({ message: 'Expense updated successfully', expense });
    } catch (err) {
        await t.rollback();
        res.status(500).json({ error: err.message });
    }
};

exports.deleteExpense = async (req, res) => {
    const t = await sequelize.transaction();
    try {
        const expenseId = req.params.id;
        await ExpenseSplit.destroy({ where: { expense_id: expenseId }, transaction: t });
        await ExpensePayer.destroy({ where: { expense_id: expenseId }, transaction: t });
        const deleted = await Expense.destroy({ where: { id: expenseId }, transaction: t });
        if (!deleted) {
            await t.rollback();
            return res.status(404).json({ error: 'Expense not found' });
        }
        await t.commit();
        res.json({ message: 'Expense deleted successfully' });
    } catch (err) {
        await t.rollback();
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
