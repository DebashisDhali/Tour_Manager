const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, sequelize } = require('../models');

exports.syncData = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { userId, unsyncedData } = req.body;
    
    // 1. Process Unsynced Data from Client (Push)
    if (unsyncedData) {
      const { tours, users, expenses, splits, payers, settlements } = unsyncedData;

      // 1. Bulk Upsert Users
      if (users && users.length > 0) {
        console.log(`📡 Sync: Bulk pushing ${users.length} users...`);
        await User.bulkCreate(users.map(u => ({
          id: u.id,
          name: u.name,
          phone: u.phone,
          email: u.email,
          avatar_url: u.avatarUrl,
          purpose: u.purpose,
          updated_at: new Date()
        })), { 
          transaction,
          updateOnDuplicate: ['name', 'phone', 'email', 'avatar_url', 'purpose', 'updated_at']
        });
      }

      // 2. Sync Tours (Individual due to association logic)
      if (tours && tours.length > 0) {
        console.log(`📡 Sync: Pushing ${tours.length} tours...`);
        for (const t of tours) {
          await Tour.upsert({ 
            id: t.id, 
            name: t.name, 
            created_by: t.createdBy, 
            invite_code: t.inviteCode,
            start_date: t.startDate, 
            end_date: t.endDate 
          }, { transaction });

          const tourInstance = await Tour.findByPk(t.id, { transaction });
          if (tourInstance && t.createdBy) {
            const creator = await User.findByPk(t.createdBy, { transaction });
            if (creator) await tourInstance.addUser(creator, { transaction });
          }
        }
      }

      // 3. Bulk Upsert Expenses
      if (expenses && expenses.length > 0) {
        console.log(`📡 Sync: Bulk pushing ${expenses.length} expenses...`);
        await Expense.bulkCreate(expenses.map(e => ({
          id: e.id,
          tour_id: e.tourId,
          payer_id: e.payerId,
          amount: e.amount,
          title: e.title,
          category: e.category,
          date: e.createdAt
        })), { 
          transaction,
          updateOnDuplicate: ['amount', 'title', 'category', 'date', 'payer_id']
        });
      }

      // 4. Bulk Upsert Splits
      if (splits && splits.length > 0) {
        await ExpenseSplit.bulkCreate(splits.map(s => ({
          id: s.id,
          expense_id: s.expenseId,
          user_id: s.userId,
          amount: s.amount
        })), { 
          transaction,
          updateOnDuplicate: ['amount']
        });
      }

      // 5. Bulk Upsert Payers
      if (payers && payers.length > 0) {
        await ExpensePayer.bulkCreate(payers.map(p => ({
          id: p.id,
          expense_id: p.expenseId,
          user_id: p.userId,
          amount: p.amount
        })), { 
          transaction,
          updateOnDuplicate: ['amount']
        });
      }

      // 6. Bulk Upsert Settlements
      if (settlements && settlements.length > 0) {
        await Settlement.bulkCreate(settlements.map(s => ({
          id: s.id,
          tour_id: s.tourId,
          from_id: s.fromId,
          to_id: s.toId,
          amount: s.amount,
          date: s.date
        })), { 
          transaction,
          updateOnDuplicate: ['amount', 'date']
        });
      }

      // 7. Sync Tour Members (Manually as they are a junction table without a separate primary ID usually)
      if (unsyncedData.members && unsyncedData.members.length > 0) {
        console.log(`📡 Sync: Pushing ${unsyncedData.members.length} member connections...`);
        for (const m of unsyncedData.members) {
           const tour = await Tour.findByPk(m.tourId, { transaction });
           const user = await User.findByPk(m.userId, { transaction });
           if (tour && user) {
             await tour.addUser(user, { transaction });
             // Update left_at if present
             if (m.leftAt) {
               await (sequelize.model('TourMember')).update(
                 { left_at: m.leftAt },
                 { where: { tour_id: m.tourId, user_id: m.userId }, transaction }
               );
             }
           }
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
