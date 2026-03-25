const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, sequelize } = require('../models');
const { Op } = require('sequelize');

exports.syncData = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { userId, unsyncedData, lastSync } = req.body;
    const lastSyncDate = lastSync ? new Date(lastSync) : new Date(0);
    const now = new Date();

    if (!userId) {
      if (transaction) await transaction.rollback();
      return res.status(400).json({ error: "userId is required" });
    }

    // Ensure user exists
    await User.upsert({ id: userId, updated_at: now }, { transaction });

    // 1. Process Unsynced Data from Client (Push)
    if (unsyncedData) {
      const { tours, users, expenses, splits, payers, settlements, incomes, members } = unsyncedData;

      if (users?.length > 0) {
        await User.bulkCreate(users.map(u => ({
          id: u.id, name: u.name, phone: u.phone, email: u.email,
          avatar_url: u.avatarUrl, purpose: u.purpose, updated_at: now
        })), { transaction, updateOnDuplicate: ['name', 'phone', 'email', 'avatar_url', 'purpose', 'updated_at'] });
      }

      if (tours?.length > 0) {
        // Bulk Upsert Tours
        await Tour.bulkCreate(tours.map(t => ({
          id: t.id, name: t.name, created_by: t.createdBy, 
          invite_code: t.inviteCode, start_date: t.startDate, 
          end_date: t.endDate, updated_at: now 
        })), { transaction, updateOnDuplicate: ['name', 'created_by', 'invite_code', 'start_date', 'end_date', 'updated_at'] });
        
        // Ensure creators are members (for tours created offline)
        const creatorMemberships = tours
          .filter(t => t.createdBy)
          .map(t => ({ 
            tour_id: t.id, 
            user_id: t.createdBy, 
            status: 'active', 
            role: 'admin', // Owner should be admin
            joined_at: now, 
            updated_at: now 
          }));
        
        if (creatorMemberships.length > 0) {
           await TourMember.bulkCreate(creatorMemberships, { transaction, ignoreDuplicates: true, updateOnDuplicate: ['role'] });
        }
      }

      if (expenses?.length > 0) {
        await Expense.bulkCreate(expenses.map(e => ({
          id: e.id, tour_id: e.tourId, payer_id: e.payerId || null, amount: e.amount,
          title: e.title, category: e.category, mess_cost_type: e.messCostType, date: e.createdAt, updated_at: now
        })), { transaction, updateOnDuplicate: ['amount', 'title', 'category', 'date', 'payer_id', 'mess_cost_type', 'updated_at'] });
      }

      if (splits?.length > 0) {
        await ExpenseSplit.bulkCreate(splits.map(s => ({ id: s.id, expense_id: s.expenseId, user_id: s.userId, amount: s.amount })), { transaction, updateOnDuplicate: ['amount'] });
      }

      if (payers?.length > 0) {
        await ExpensePayer.bulkCreate(payers.map(p => ({ id: p.id, expense_id: p.expenseId, user_id: p.userId, amount: p.amount })), { transaction, updateOnDuplicate: ['amount'] });
      }

      if (settlements?.length > 0) {
        await Settlement.bulkCreate(settlements.map(s => ({
          id: s.id, tour_id: s.tourId, from_id: s.fromId, to_id: s.toId, amount: s.amount, date: s.date, updated_at: now
        })), { transaction, updateOnDuplicate: ['amount', 'date', 'updated_at'] });
      }
      
      if (incomes?.length > 0) {
        await ProgramIncome.bulkCreate(incomes.map(i => ({
          id: i.id, tour_id: i.tourId, amount: i.amount, source: i.source,
          description: i.description, collected_by: i.collectedBy, date: i.date, updated_at: now
        })), { transaction, updateOnDuplicate: ['amount', 'source', 'description', 'collected_by', 'date', 'updated_at'] });
      }

      if (members?.length > 0) {
        // Bulk Upsert Tour Memberships
        await TourMember.bulkCreate(members.map(m => ({
          tour_id: m.tourId,
          user_id: m.userId,
          status: m.leftAt ? 'removed' : 'active',
          removed_at: m.leftAt || null,
          meal_count: m.mealCount || 0.0,
          updated_at: now
        })), { 
          transaction, 
          updateOnDuplicate: ['status', 'removed_at', 'meal_count', 'updated_at'] 
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

    // Fetch only tours that have been updated since lastSync OR have updated children
    const pullCondition = { [Op.gt]: lastSyncDate };

    const tours = await Tour.findAll({
      where: { 
        id: tourIds,
        // Optional optimization: Only pull tours that had ANY change? 
        // But sub-resource children might have changed. 
      },
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
    if (transaction && !transaction.finished) await transaction.rollback();
    res.status(500).json({ error: "Sync failed", details: err.message });
  }
};
