const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, sequelize } = require('../models');

exports.syncData = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { userId, unsyncedData } = req.body;
    
    // 1. Process Unsynced Data from Client (Push)
    if (unsyncedData) {
      const { tours, users, expenses, splits, payers, settlements } = unsyncedData;

      if (users) {
        console.log(`📡 Sync: Pushing ${users.length} users...`);
        for (const u of users) {
          await User.upsert({ 
            id: u.id, 
            name: u.name, 
            phone: u.phone,
            email: u.email,
            avatar_url: u.avatarUrl,
            purpose: u.purpose
          }, { transaction });
        }
      }

      if (tours) {
        console.log(`📡 Sync: Pushing ${tours.length} tours...`);
        for (const t of tours) {
          const [tourRecord] = await Tour.upsert({ 
            id: t.id, 
            name: t.name, 
            created_by: t.createdBy, 
            invite_code: t.inviteCode,
            start_date: t.startDate, 
            end_date: t.endDate 
          }, { transaction });

          // Ensure creator is a member
          const creator = await User.findByPk(t.createdBy, { transaction });
          if (creator) {
            await tourRecord.addUser(creator, { transaction });
          }
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

      if (payers) {
        for (const p of payers) {
          await ExpensePayer.upsert({
            id: p.id,
            expense_id: p.expenseId,
            user_id: p.userId,
            amount: p.amount
          }, { transaction });
        }
      }

      if (settlements) {
        for (const s of settlements) {
          await Settlement.upsert({
            id: s.id,
            tour_id: s.tourId,
            from_id: s.fromId,
            to_id: s.toId,
            amount: s.amount,
            date: s.date
          }, { transaction });
        }
      }
    }

    await transaction.commit();

    // 2. Fetch All Data for the User's Tours to send back (Pull)
    const userWithTours = await User.findByPk(userId, {
      include: [{
        model: Tour,
        include: [
          { model: User }, // Members
          { 
            model: Expense,
            include: [ExpenseSplit, ExpensePayer]
          },
          { model: Settlement }
        ]
      }]
    });

    res.json({
      timestamp: new Date().toISOString(),
      tours: userWithTours ? userWithTours.Tours : []
    });

  } catch (err) {
    if (transaction) await transaction.rollback();
    console.error("Sync Error:", err);
    res.status(500).json({ error: err.message });
  }
};
