const { Tour, User, Expense, ExpenseSplit, sequelize } = require('../models');

exports.syncData = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { userId, unsyncedData } = req.body;
    
    // 1. Process Unsynced Data from Client
    if (unsyncedData) {
      const { tours, users, expenses, splits } = unsyncedData;

      if (users) {
        for (const u of users) {
          await User.upsert({ id: u.id, name: u.name, phone: u.phone }, { transaction });
        }
      }

      if (tours) {
        for (const t of tours) {
          await Tour.upsert({ 
            id: t.id, 
            name: t.name, 
            created_by: t.createdBy, 
            invite_code: t.inviteCode,
            start_date: t.startDate, 
            end_date: t.endDate 
          }, { transaction });
        }
      }

      if (expenses) {
        for (const e of expenses) {
          await Expense.upsert({
            id: e.id,
            tour_id: e.tourId,
            payer_id: e.payerId,
            amount: e.amount,
            title: e.title,
            category: e.category,
            date: e.createdAt
          }, { transaction });
        }
      }

      if (splits) {
        for (const s of splits) {
          await ExpenseSplit.upsert({
            id: s.id,
            expense_id: s.expenseId,
            user_id: s.userId,
            amount: s.amount
          }, { transaction });
        }
      }
    }

    await transaction.commit();

    // 2. Fetch All Data for the User's Tours to send back (Pull)
    const user = await User.findByPk(userId, {
      include: [{
        model: Tour,
        include: [
          { model: User }, // Members
          { 
            model: Expense,
            include: [ExpenseSplit]
          }
        ]
      }]
    });

    res.json({
      timestamp: new Date().toISOString(),
      tours: user ? user.Tours : []
    });

  } catch (err) {
    if (transaction) await transaction.rollback();
    res.status(500).json({ error: err.message });
  }
};
