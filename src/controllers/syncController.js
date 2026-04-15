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
    
    try {
      // Update user's last activity
      await User.update({ updated_at: now, is_registered: true }, { 
        where: { id: userId },
        transaction 
      });

      // 1. Process Unsynced Data from Client (Push)
      if (unsyncedData) {
        const { tours, users, expenses, splits, payers, settlements, incomes, members, joinRequests } = unsyncedData;

        // 1.1 Process Users
        if (users?.length > 0) {
          for (const u of users) {
             try {
               await User.upsert({
                 id: u.id, name: u.name, phone: u.phone, email: u.email,
                 avatar_url: u.avatarUrl, purpose: u.purpose, updated_at: now
               }, { transaction });
             } catch (e) { console.error(`⚠️ User Upsert Fail [${u.id}]:`, e.message); }
          }
        }

        // 1.2 Process Tours
        if (tours?.length > 0) {
          for (const t of tours) {
             try {
               await Tour.upsert({
                 id: t.id, name: t.name, created_by: t.createdBy, 
                 invite_code: t.inviteCode, start_date: t.startDate, 
                 end_date: t.endDate, updated_at: now 
               }, { transaction });
               
               if (t.createdBy) {
                 await TourMember.upsert({ 
                   tour_id: t.id, user_id: t.createdBy, 
                   status: 'active', role: 'admin', 
                   joined_at: t.startDate || now, updated_at: now 
                 }, { transaction });
               }
             } catch (e) { console.error(`⚠️ Tour Upsert Fail [${t.id}]:`, e.message); }
          }
        }

        // 1.3 Process Tour Members
        if (members?.length > 0) {
          for (const m of members) {
             try {
               await TourMember.upsert({
                 tour_id: m.tourId, user_id: m.userId,
                 status: m.leftAt ? 'removed' : 'active',
                 removed_at: m.leftAt || null,
                 role: m.role || 'viewer',
                 meal_count: m.mealCount || 0.0,
                 updated_at: now
               }, { transaction });
             } catch (e) { console.error(`⚠️ Member Upsert Fail [${m.tourId}-${m.userId}]:`, e.message); }
          }
        }

        // 1.4 Bulk Create for Performance
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

        if (joinRequests?.length > 0) {
          await JoinRequest.bulkCreate(joinRequests.map(jr => ({
            id: jr.id, tour_id: jr.tourId, user_id: jr.userId, user_name: jr.userName || 'Unknown', status: jr.status || 'pending', updated_at: now
          })), { transaction, updateOnDuplicate: ['status', 'updated_at'], conflictAttributes: ['id'] });
        }
      }

      await transaction.commit();
      transaction = null;
    } catch (pushErr) {
      console.error('❌ Push Sync Phase Failed:', pushErr);
      if (transaction) await transaction.rollback();
      transaction = null;
      // We don't throw here so the user can still pull data if push partially failed or is blocked
    }



    // 2. Optimized Incremental Pull
    const activeTourRecords = await TourMember.findAll({
      where: { user_id: userId, status: 'active' },
      attributes: ['tour_id'],
      raw: true
    });
    const tourIds = activeTourRecords.map(r => r.tour_id);

    // Fetch only tours and their updated children
    const pullCondition = { [Op.gt]: lastSyncDate };
    const dateCondition = lastSync ? { updated_at: pullCondition } : {};

    // Parallel fetch for speed (Vercel has a 10s limit)
    const [
      updatedExpenses,
      updatedSettlements,
      updatedIncomes,
      updatedJoinRequests,
      updatedMembers,
      allTours
    ] = await Promise.all([
      Expense.findAll({ where: { tour_id: tourIds, ...dateCondition }, include: [ExpenseSplit, ExpensePayer] }),
      Settlement.findAll({ where: { tour_id: tourIds, ...dateCondition } }),
      ProgramIncome.findAll({ where: { tour_id: tourIds, ...dateCondition } }),
      JoinRequest.findAll({ where: { tour_id: tourIds, ...dateCondition } }),
      TourMember.findAll({ where: { tour_id: tourIds, ...dateCondition }, include: [User] }),
      Tour.findAll({ where: { id: tourIds }, raw: true })
    ]);

    // Reconstruct nested structure
    const toursData = allTours.map(tour => {
      return {
        ...tour,
        Expenses: updatedExpenses.filter(e => e.tour_id === tour.id),
        Settlements: updatedSettlements.filter(s => s.tour_id === tour.id),
        ProgramIncomes: updatedIncomes.filter(i => i.tour_id === tour.id),
        JoinRequests: updatedJoinRequests.filter(jr => jr.tour_id === tour.id),
        Users: updatedMembers.filter(m => m.tour_id === tour.id).map(m => {
           const member = m.get({ plain: true });
           if (member.User) {
             const user = member.User;
             delete member.User;
             return { ...user, TourMember: member };
           }
           return member;
        })
      };
    });

    res.json({
      timestamp: now.toISOString(),
      tours: toursData,
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
