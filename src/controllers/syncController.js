const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, JoinRequest, sequelize } = require('../models');
const { Op } = require('sequelize');

exports.syncData = async (req, res) => {
  let transaction;
  let pushPhaseError = null;
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
               if (u.isDeleted) {
                 await User.destroy({ where: { id: u.id }, transaction });
               } else {
                  await User.upsert({
                    id: u.id.toLowerCase(), name: u.name, phone: u.phone, email: u.email,
                    avatar_url: u.avatarUrl, purpose: u.purpose, updated_at: now
                  }, { transaction });
               }
             } catch (e) { console.error(`⚠️ User Sync Fail [${u.id}]:`, e.message); }
          }
        }

        // 1.2 Process Tours
        if (tours?.length > 0) {
          for (const t of tours) {
             if (t.isDeleted) {
               await Tour.destroy({ where: { id: t.id }, transaction });
             } else {
               // Ensure the creator exists on the server to avoid FK issues with TourMember
               // We don't have all user info here, but we can create a shell if missing
               if (t.createdBy) {
                  const creatorId = t.createdBy.toLowerCase();
                  await User.findOrCreate({
                    where: { id: creatorId },
                    defaults: { id: creatorId, name: 'Cloud User', updated_at: now },
                    transaction
                  });
                }

                await Tour.upsert({
                  id: t.id.toLowerCase(), name: t.name, created_by: t.createdBy ? t.createdBy.toLowerCase() : null, 
                  invite_code: t.inviteCode || null, start_date: t.startDate || null,
                  end_date: t.endDate || null, updated_at: now, purpose: t.purpose || 'tour'
                }, { transaction });
                
                if (t.createdBy) {
                  await TourMember.upsert({ 
                    tour_id: t.id.toLowerCase(), user_id: t.createdBy.toLowerCase(), 
                    status: 'active', role: 'admin', 
                    joined_at: t.startDate || now, updated_at: now 
                  }, { transaction });
                }
             }
          }
        }

        // 1.3 Process Tour Members
        if (members?.length > 0) {
          for (const m of members) {
             try {
               // Members are more of status changes than hard deletes usually, 
               // but we follow the flag if provided.
               if (m.isDeleted) {
                  await TourMember.destroy({ where: { tour_id: m.tourId, user_id: m.userId }, transaction });
               } else {
                  const mTourId = m.tourId.toLowerCase();
                  const mUserId = m.userId.toLowerCase();
                  await TourMember.upsert({
                    tour_id: mTourId, user_id: mUserId,
                    status: m.status || (m.leftAt ? 'removed' : 'active'),
                    removed_at: m.leftAt || null,
                    role: m.role || 'viewer',
                    meal_count: m.mealCount || 0.0,
                    updated_at: now
                  }, { transaction });
               }
             } catch (e) { console.error(`⚠️ Member Sync Fail [${m.tourId}-${m.userId}]:`, e.message); }
          }
        }

        // 1.4 Bulk Operations with Delete Support
        if (expenses?.length > 0) {
          const toDelete = expenses.filter(e => e.isDeleted).map(e => e.id);
          const toUpsert = expenses.filter(e => !e.isDeleted);
          if (toDelete.length > 0) await Expense.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await Expense.bulkCreate(toUpsert.map(e => ({
              id: e.id, tour_id: e.tourId, payer_id: e.payerId || null, amount: e.amount,
              title: e.title, category: e.category, mess_cost_type: e.messCostType, date: e.createdAt, updated_at: now
            })), { transaction, updateOnDuplicate: ['amount', 'title', 'category', 'date', 'payer_id', 'mess_cost_type', 'updated_at'], conflictAttributes: ['id'] });
          }
        }

        if (splits?.length > 0) {
          const toDelete = splits.filter(s => s.isDeleted).map(s => s.id);
          const toUpsert = splits.filter(s => !s.isDeleted);
          if (toDelete.length > 0) await ExpenseSplit.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await ExpenseSplit.bulkCreate(toUpsert.map(s => ({ id: s.id, expense_id: s.expenseId, user_id: s.userId, amount: s.amount })), { transaction, updateOnDuplicate: ['amount'], conflictAttributes: ['id'] });
          }
        }

        if (payers?.length > 0) {
          const toDelete = payers.filter(p => p.isDeleted).map(p => p.id);
          const toUpsert = payers.filter(p => !p.isDeleted);
          if (toDelete.length > 0) await ExpensePayer.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await ExpensePayer.bulkCreate(toUpsert.map(p => ({ id: p.id, expense_id: p.expenseId, user_id: p.userId, amount: p.amount })), { transaction, updateOnDuplicate: ['amount'], conflictAttributes: ['id'] });
          }
        }

        if (settlements?.length > 0) {
          const toDelete = settlements.filter(s => s.isDeleted).map(s => s.id);
          const toUpsert = settlements.filter(s => !s.isDeleted);
          if (toDelete.length > 0) await Settlement.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await Settlement.bulkCreate(toUpsert.map(s => ({
              id: s.id, tour_id: s.tourId, from_id: s.fromId, to_id: s.toId, amount: s.amount, date: s.date, updated_at: now
            })), { transaction, updateOnDuplicate: ['amount', 'date', 'updated_at'], conflictAttributes: ['id'] });
          }
        }
        
        if (incomes?.length > 0) {
          const toDelete = incomes.filter(i => i.isDeleted).map(i => i.id);
          const toUpsert = incomes.filter(i => !i.isDeleted);
          if (toDelete.length > 0) await ProgramIncome.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await ProgramIncome.bulkCreate(toUpsert.map(i => ({
              id: i.id, tour_id: i.tourId, amount: i.amount, source: i.source,
              description: i.description, collected_by: i.collectedBy, date: i.date, updated_at: now
            })), { transaction, updateOnDuplicate: ['amount', 'source', 'description', 'collected_by', 'date', 'updated_at'], conflictAttributes: ['id'] });
          }
        }

        if (joinRequests?.length > 0) {
          const toDelete = joinRequests.filter(jr => jr.isDeleted).map(jr => jr.id);
          const toUpsert = joinRequests.filter(jr => !jr.isDeleted);
          if (toDelete.length > 0) await JoinRequest.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await JoinRequest.bulkCreate(toUpsert.map(jr => ({
              id: jr.id, tour_id: jr.tourId, user_id: jr.userId, user_name: jr.userName || 'Unknown', status: jr.status || 'pending'
            })), { transaction, updateOnDuplicate: ['status'], conflictAttributes: ['id'] });
          }
        }
      }

      await transaction.commit();
      transaction = null;
      console.log('✅ Push phase completed successfully.');
    } catch (pushErr) {
      console.error('⚠️ Push Sync Phase had errors (non-fatal, continuing to pull):', pushErr.message);
      pushPhaseError = pushErr.message; // Store error to send to client
      if (transaction) {
        try { await transaction.rollback(); } catch(rbErr) { /* ignore */ }
        transaction = null;
      }
    }



    // Fetch ALL tour IDs where the user is an active member
    const activeTourRecords = await TourMember.findAll({
      where: { 
        user_id: sequelize.where(
          sequelize.fn('LOWER', sequelize.cast(sequelize.col('user_id'), 'text')),
          userId.toLowerCase()
        ), 
        status: 'active' 
      },
      attributes: ['tour_id'],
      raw: true
    });
    const tourIds = activeTourRecords.map(r => r.tour_id);
    console.log(`📡 Pulling data for User: ${userId}. Involved Tours: [${tourIds.join(', ')}]`);

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
      JoinRequest.findAll({ where: { tour_id: tourIds } }),  // no updated_at column — always fetch all
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
      pushSuccess: pushPhaseError === null,
      pushError: pushPhaseError,
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
