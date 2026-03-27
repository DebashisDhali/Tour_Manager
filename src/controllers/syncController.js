const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, JoinRequest, sequelize } = require('../models');
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
      const { tours, users, expenses, splits, payers, settlements, incomes, members, joinRequests } = unsyncedData;

      if (users?.length > 0) {
        // Individual upserts handle unique constraints (phone/email) without crashing the whole sync
        for (const u of users) {
          try {
            await User.upsert({
              id: u.id, name: u.name, phone: u.phone, email: u.email,
              avatar_url: u.avatarUrl, purpose: u.purpose, updated_at: now
            }, { transaction });
          } catch (e) {
            console.error(`⚠️ Sync User Skip [${u.id}]: ${e.message}`);
          }
        }
      }

      if (tours?.length > 0) {
        for (const t of tours) {
          try {
            // Bulk Upsert Tours
            await Tour.upsert({
              id: t.id, name: t.name, created_by: t.createdBy, 
              invite_code: t.inviteCode, start_date: t.startDate, 
              end_date: t.endDate, updated_at: now 
            }, { transaction });
            
            // Ensure creators are members (for tours created offline)
            if (t.createdBy) {
              await TourMember.upsert({ 
                tour_id: t.id, 
                user_id: t.createdBy, 
                status: 'active', 
                role: 'admin', 
                joined_at: now, 
                updated_at: now 
              }, { transaction });
            }
          } catch (e) {
            console.error(`⚠️ Sync Tour Skip [${t.id}]: ${e.message}`);
          }
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
        // Members are few, using upsert is safer for composite keys
        for (const m of members) {
          try {
            await TourMember.upsert({
              tour_id: m.tourId,
              user_id: m.userId,
              status: m.leftAt ? 'removed' : 'active',
              removed_at: m.leftAt || null,
              role: m.role || 'viewer',
              meal_count: m.mealCount || 0.0,
              updated_at: now
            }, { transaction });
          } catch (err) { console.error(`⚠️ Sync Member Skip [${m.tourId}-${m.userId}]: ${err.message}`); }
        }
      }

      if (joinRequests?.length > 0) {
        await JoinRequest.bulkCreate(joinRequests.map(jr => ({
          id: jr.id,
          tour_id: jr.tourId,
          user_id: jr.userId,
          user_name: jr.userName || 'Unknown',
          status: jr.status || 'pending',
          updated_at: now
        })), { 
          transaction, 
          updateOnDuplicate: ['status', 'updated_at'],
          conflictAttributes: ['id']
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
        },
        {
          model: JoinRequest,
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
