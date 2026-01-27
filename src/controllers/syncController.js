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
          try {
            await Tour.upsert({ 
              id: t.id, 
              name: t.name, 
              created_by: t.createdBy, 
              invite_code: t.inviteCode,
              start_date: t.startDate, 
              end_date: t.endDate 
            }, { transaction });

            // Fetch the instance to be safe
            const tourInstance = await Tour.findByPk(t.id, { transaction });
            if (tourInstance && t.createdBy) {
              const creator = await User.findByPk(t.createdBy, { transaction });
              if (creator) {
                await tourInstance.addUser(creator, { transaction });
              }
            }
          } catch (err) {
            console.error(`Error syncing tour ${t.id}:`, err);
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
    console.log(`✅ Sync: Data for user ${userId} pushed successfully.`);

    // 2. Fetch All Data for the User's Tours to send back (Pull)
    // Optimized: Fetch tours first, then fetch details to avoid massive join slowdown
    const tours = await Tour.findAll({
      include: [{
        model: User,
        where: { id: userId },
        attributes: [] // Just to filter tours this user belongs to
      }]
    });

    const tourIds = tours.map(t => t.id);
    
    // Fetch full data for these tours
    const fullTours = await Tour.findAll({
      where: { id: tourIds },
      include: [
        { model: User }, // Members
        { 
          model: Expense,
          include: [ExpenseSplit, ExpensePayer]
        },
        { model: Settlement }
      ]
    });

    res.json({
      timestamp: new Date().toISOString(),
      tours: fullTours
    });

  } catch (err) {
    if (transaction && !transaction.finished) {
      try {
        await transaction.rollback();
      } catch (rbErr) {
        console.error("Rollback Error:", rbErr);
      }
    }
    console.error("Sync Error:", err);
    res.status(500).json({ 
      error: "Synchronization failed", 
      details: err.message,
      stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });
  }
};
