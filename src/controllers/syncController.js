const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, sequelize } = require('../models');
const { Op } = require('sequelize');

exports.syncData = async (req, res) => {
  let transaction;
  try {
    const { userId, unsyncedData, lastSync } = req.body;
    
    // Validate lastSync date
    let lastSyncDate = new Date(0);
    if (lastSync && lastSync !== 'null' && lastSync !== 'undefined') {
      const d = new Date(lastSync);
      if (!isNaN(d.getTime())) {
        lastSyncDate = d;
      }
    }
    
    const now = new Date();

    if (!userId) {
      return res.status(400).json({ error: "userId is required" });
    }

    transaction = await sequelize.transaction();
    
    // Update user's last activity (since they passed auth, they must exist)
    await User.update({ updated_at: now, is_registered: true }, { 
      where: { id: userId },
      transaction 
    });

    // 1. Process Unsynced Data from Client (Push)
    if (unsyncedData) {
      const { tours, users, expenses, splits, payers, settlements, incomes, members } = unsyncedData;

      if (users?.length > 0) {
        await User.bulkCreate(users.map(u => ({
          id: u.id, name: u.name, phone: u.phone, email: u.email,
          avatar_url: u.avatarUrl, purpose: u.purpose, updated_at: now
        })), { transaction, updateOnDuplicate: ['name', 'phone', 'email', 'avatar_url', 'purpose', 'updated_at'], conflictAttributes: ['id'] });
      }

      if (tours?.length > 0) {
        // Bulk Upsert Tours
        await Tour.bulkCreate(tours.map(t => ({
          id: t.id, name: t.name, created_by: t.createdBy, 
          invite_code: t.inviteCode, start_date: t.startDate, 
          end_date: t.endDate, updated_at: now 
        })), { transaction, updateOnDuplicate: ['name', 'created_by', 'invite_code', 'start_date', 'end_date', 'updated_at'], conflictAttributes: ['id'] });
        
        // Ensure creators are members (for tours created offline)
        const creatorMemberships = tours
          .filter(t => t.createdBy)
          .map(t => ({ 
            tour_id: t.id, 
            user_id: t.createdBy, 
            status: 'active', 
            role: 'admin', 
            joined_at: now, 
            updated_at: now 
          }));
        
        if (creatorMemberships.length > 0) {
           await TourMember.bulkCreate(creatorMemberships, { transaction, updateOnDuplicate: ['role', 'updated_at'], conflictAttributes: ['tour_id', 'user_id'] });
        }
      }

      if (expenses?.length > 0) {
        await Expense.bulkCreate(expenses.map(e => ({
          id: e.id, tour_id: e.tourId, payer_id: e.payerId || null, amount: e.amount,
          title: e.title, category: e.category, mess_cost_type: e.messCostType, date: e.createdAt, updated_at: now
        })), { transaction, updateOnDuplicate: ['amount', 'title', 'category', 'date', 'payer_id', 'mess_cost_type', 'updated_at'], conflictAttributes: ['id'] });
      }

      if (splits?.length > 0) {
        await ExpenseSplit.bulkCreate(splits.map(s => ({ id: s.id, expense_id: s.expenseId, user_id: s.userId, amount: s.amount })), { transaction, updateOnDuplicate: ['amount'], conflictAttributes: ['id'] });
      }

      if (payers?.length > 0) {
        await ExpensePayer.bulkCreate(payers.map(p => ({ id: p.id, expense_id: p.expenseId, user_id: p.userId, amount: p.amount })), { transaction, updateOnDuplicate: ['amount'], conflictAttributes: ['id'] });
      }

      if (settlements?.length > 0) {
        await Settlement.bulkCreate(settlements.map(s => ({
          id: s.id, tour_id: s.tourId, from_id: s.fromId, to_id: s.toId, amount: s.amount, date: s.date, updated_at: now
        })), { transaction, updateOnDuplicate: ['amount', 'date', 'updated_at'], conflictAttributes: ['id'] });
      }
      
      if (incomes?.length > 0) {
        await ProgramIncome.bulkCreate(incomes.map(i => ({
          id: i.id, tour_id: i.tourId, amount: i.amount, source: i.source,
          description: i.description, collected_by: i.collectedBy, date: i.date, updated_at: now
        })), { transaction, updateOnDuplicate: ['amount', 'source', 'description', 'collected_by', 'date', 'updated_at'], conflictAttributes: ['id'] });
      }

      if (members?.length > 0) {
        await TourMember.bulkCreate(members.map(m => ({
          tour_id: m.tourId,
          user_id: m.userId,
          status: m.leftAt ? 'removed' : 'active',
          removed_at: m.leftAt || null,
          role: m.role || 'viewer',
          meal_count: m.mealCount || 0.0,
          updated_at: now
        })), { 
          transaction, 
          updateOnDuplicate: ['status', 'removed_at', 'meal_count', 'role', 'updated_at'],
          conflictAttributes: ['tour_id', 'user_id']
        });
      }
    }

    await transaction.commit();

    // 2. Optimized Incremental Pull
    const activeTourRecords = await TourMember.findAll({
      where: { user_id: userId, status: 'active' },
      attributes: ['tour_id'],
      raw: true
    });
    const tourIds = activeTourRecords.map(r => r.tour_id);

    // Fetch only tours and their updated children
    const pullCondition = { [Op.gt]: lastSyncDate };

    const tours = await Tour.findAll({
      where: { id: tourIds },
      include: [
        { 
          model: User,
          through: { 
            attributes: ['status', 'joined_at', 'removed_at', 'meal_count'],
            where: lastSync ? { updated_at: pullCondition } : {} 
          },
          required: false 
        }, 
        { 
          model: Expense,
          where: lastSync ? { updated_at: pullCondition } : {},
          required: false,
          include: [ExpenseSplit, ExpensePayer]
        },
        { 
          model: Settlement, 
          where: lastSync ? { updated_at: pullCondition } : {}, 
          required: false 
        },
        { 
          model: ProgramIncome, 
          where: lastSync ? { updated_at: pullCondition } : {}, 
          required: false 
        }
      ]
    });

    res.json({
      timestamp: now.toISOString(),
      tours: tours,
      allTourIds: tourIds 
    });

  } catch (err) {
    console.error('❌ Sync Error Details:', err);
    if (transaction) await transaction.rollback();
    res.status(500).json({ 
      error: "Sync failed", 
      message: err.message,
      stack: process.env.NODE_ENV !== 'production' ? err.stack : undefined
    });
  }
};
