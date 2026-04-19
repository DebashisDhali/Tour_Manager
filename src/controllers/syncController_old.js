const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, JoinRequest, sequelize } = require('../models');
const { Op } = require('sequelize');

exports.syncData = async (req, res) => {
  let transaction;
  let pushPhaseError = null;

  try {
    console.log('=== 🚀 SYNC START ===');
    const { userId, unsyncedData, lastSync } = req.body;
    
    if (!userId) {
      console.warn('⚠️ userId is missing from request');
      return res.status(400).json({ error: "userId is required" });
    }

    const normalizedUserId = userId.toLowerCase();
    console.log(`📍 User ID normalized: ${normalizedUserId}`);
    
    // Validate lastSync date
    let lastSyncDate = new Date(0);
    if (lastSync && lastSync !== 'null' && lastSync !== 'undefined') {
      const d = new Date(lastSync);
      if (!isNaN(d.getTime())) {
        lastSyncDate = d;
      }
    }
    
    const now = new Date();
    console.log(`🕐 Sync timestamp: ${now.toISOString()}`);

    // ========== PUSH PHASE ==========
    console.log('📤 Starting PUSH phase...');
    try {
      transaction = await sequelize.transaction();
      console.log('✅ Transaction created');

      // Verify user exists in database
      const userExists = await User.findByPk(normalizedUserId);
      if (!userExists) {
        console.log(`👤 Creating new user record for: ${normalizedUserId}`);
        await User.create({ id: normalizedUserId, name: 'Mobile User' }, { transaction });
      }

      // Update user's registration status
      const updateResult = await User.update({ is_registered: true }, { 
        where: { id: normalizedUserId },
        transaction 
      });
      console.log(`✅ User updated: ${updateResult[0]} rows affected`);

      // Process unsynced data
      if (unsyncedData) {
        console.log('📦 Processing unsynced data...');
        const { tours, users, expenses, splits, payers, settlements, incomes, members, joinRequests } = unsyncedData;

        // Process users
        if (users?.length > 0) {
          console.log(`  👥 Processing ${users.length} user(s)...`);
          for (const u of users) {
            try {
              if (u.isDeleted) {
                await User.destroy({ where: { id: u.id }, transaction });
              } else {
                await User.upsert({
                  id: u.id.toLowerCase(), name: u.name, phone: u.phone, email: u.email,
                  avatar_url: u.avatarUrl, purpose: u.purpose
                }, { transaction });
              }
            } catch (e) { 
              console.error(`  ⚠️ User sync failed [${u.id}]:`, e.message);
            }
          }
          console.log(`  ✅ Users processed`);
        }

        // Process tours
        if (tours?.length > 0) {
          console.log(`  🏕️  Processing ${tours.length} tour(s)...`);
          for (const t of tours) {
            try {
              if (t.isDeleted) {
                await Tour.destroy({ where: { id: t.id.toLowerCase() }, transaction });
              } else {
                if (t.createdBy) {
                  const creatorId = t.createdBy.toLowerCase();
                  await User.findOrCreate({
                    where: { id: creatorId },
                    defaults: { id: creatorId, name: 'Cloud User' },
                    transaction
                  });
                }

                await Tour.upsert({
                  id: t.id.toLowerCase(), name: t.name, created_by: t.createdBy ? t.createdBy.toLowerCase() : null,
                  invite_code: t.inviteCode || null, start_date: t.startDate || null,
                  end_date: t.endDate || null, purpose: t.purpose || 'tour'
                }, { transaction });

                if (t.createdBy) {
                  await TourMember.upsert({ 
                    tour_id: t.id.toLowerCase(), user_id: t.createdBy.toLowerCase(), 
                    status: 'active', role: 'admin', 
                    joined_at: t.startDate || now
                  }, { transaction });
                }
              }
            } catch (e) {
              console.error(`  ⚠️ Tour sync failed [${t.id}]:`, e.message);
            }
          }
          console.log(`  ✅ Tours processed`);
        }

        // Process members
        if (members?.length > 0) {
          console.log(`  👫 Processing ${members.length} member(s)...`);
          for (const m of members) {
            try {
              if (m.isDeleted) {
                await TourMember.destroy({ where: { tour_id: m.tourId.toLowerCase(), user_id: m.userId.toLowerCase() }, transaction });
              } else {
                await TourMember.upsert({
                  tour_id: m.tourId.toLowerCase(), user_id: m.userId.toLowerCase(),
                  status: m.status || (m.leftAt ? 'removed' : 'active'),
                  removed_at: m.leftAt || null,
                  role: m.role || 'viewer',
                  meal_count: m.mealCount || 0.0
                }, { transaction });
              }
            } catch (e) { 
              console.error(`  ⚠️ Member sync failed [${m.tourId}-${m.userId}]:`, e.message);
            }
          }
          console.log(`  ✅ Members processed`);
        }

        // Process expenses
        if (expenses?.length > 0) {
          console.log(`  💰 Processing ${expenses.length} expense(s)...`);
          const toDelete = expenses.filter(e => e.isDeleted).map(e => e.id);
          const toUpsert = expenses.filter(e => !e.isDeleted);
          if (toDelete.length > 0) await Expense.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await Expense.bulkCreate(toUpsert.map(e => ({
              id: e.id, tour_id: e.tourId, payer_id: e.payerId || null, amount: e.amount,
              title: e.title, category: e.category, mess_cost_type: e.messCostType, date: e.createdAt
            })), { transaction, updateOnDuplicate: ['amount', 'title', 'category', 'date', 'payer_id', 'mess_cost_type'], conflictAttributes: ['id'] });
          }
          console.log(`  ✅ Expenses processed`);
        }

        // Process splits
        if (splits?.length > 0) {
          console.log(`  ✂️  Processing ${splits.length} split(s)...`);
          const toDelete = splits.filter(s => s.isDeleted).map(s => s.id);
          const toUpsert = splits.filter(s => !s.isDeleted);
          if (toDelete.length > 0) await ExpenseSplit.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await ExpenseSplit.bulkCreate(toUpsert.map(s => ({ id: s.id, expense_id: s.expenseId, user_id: s.userId, amount: s.amount })), { transaction, updateOnDuplicate: ['amount'], conflictAttributes: ['id'] });
          }
          console.log(`  ✅ Splits processed`);
        }

        // Process payers
        if (payers?.length > 0) {
          console.log(`  💳 Processing ${payers.length} payer(s)...`);
          const toDelete = payers.filter(p => p.isDeleted).map(p => p.id);
          const toUpsert = payers.filter(p => !p.isDeleted);
          if (toDelete.length > 0) await ExpensePayer.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await ExpensePayer.bulkCreate(toUpsert.map(p => ({ id: p.id, expense_id: p.expenseId, user_id: p.userId, amount: p.amount })), { transaction, updateOnDuplicate: ['amount'], conflictAttributes: ['id'] });
          }
          console.log(`  ✅ Payers processed`);
        }

        // Process settlements
        if (settlements?.length > 0) {
          console.log(`  🤝 Processing ${settlements.length} settlement(s)...`);
          const toDelete = settlements.filter(s => s.isDeleted).map(s => s.id);
          const toUpsert = settlements.filter(s => !s.isDeleted);
          if (toDelete.length > 0) await Settlement.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await Settlement.bulkCreate(toUpsert.map(s => ({
              id: s.id, tour_id: s.tourId, from_id: s.fromId, to_id: s.toId, amount: s.amount, date: s.date
            })), { transaction, updateOnDuplicate: ['amount', 'date'], conflictAttributes: ['id'] });
          }
          console.log(`  ✅ Settlements processed`);
        }

        // Process incomes
        if (incomes?.length > 0) {
          console.log(`  💵 Processing ${incomes.length} income(s)...`);
          const toDelete = incomes.filter(i => i.isDeleted).map(i => i.id);
          const toUpsert = incomes.filter(i => !i.isDeleted);
          if (toDelete.length > 0) await ProgramIncome.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await ProgramIncome.bulkCreate(toUpsert.map(i => ({
              id: i.id, tour_id: i.tourId, amount: i.amount, source: i.source,
              description: i.description, collected_by: i.collectedBy, date: i.date
            })), { transaction, updateOnDuplicate: ['amount', 'source', 'description', 'collected_by', 'date'], conflictAttributes: ['id'] });
          }
          console.log(`  ✅ Incomes processed`);
        }

        // Process join requests
        if (joinRequests?.length > 0) {
          console.log(`  📋 Processing ${joinRequests.length} join request(s)...`);
          const toDelete = joinRequests.filter(jr => jr.isDeleted).map(jr => jr.id);
          const toUpsert = joinRequests.filter(jr => !jr.isDeleted);
          if (toDelete.length > 0) await JoinRequest.destroy({ where: { id: toDelete }, transaction });
          if (toUpsert.length > 0) {
            await JoinRequest.bulkCreate(toUpsert.map(jr => ({
              id: jr.id, tour_id: jr.tourId, user_id: jr.userId, user_name: jr.userName || 'Unknown', status: jr.status || 'pending'
            })), { transaction, updateOnDuplicate: ['status'], conflictAttributes: ['id'] });
          }
          console.log(`  ✅ Join requests processed`);
        }
      }

      await transaction.commit();
      console.log('✅ PUSH phase completed - transaction committed');
      transaction = null;

    } catch (pushErr) {
      console.error('⚠️ PUSH phase error (continuing to PULL):', pushErr.message);
      pushPhaseError = pushErr.message;
      if (transaction) {
        try { 
          await transaction.rollback();
          console.log('✅ Transaction rolled back');
        } catch(rbErr) { 
          console.error('⚠️ Rollback failed:', rbErr.message);
        }
        transaction = null;
      }
    }

    // ========== PULL PHASE ==========
    console.log('📥 Starting PULL phase...');
    try {
      // Get all tours for this user
      console.log(`🔍 Querying tours for user ${normalizedUserId}...`);
      const activeTourRecords = await TourMember.findAll({
        where: { 
          user_id: normalizedUserId,
          status: 'active' 
        },
        attributes: ['tour_id'],
        raw: true
      });
      console.log(`✅ Found ${activeTourRecords.length} active tours`);

      const tourIds = activeTourRecords.map(r => r.tour_id);
      if (tourIds.length === 0) {
        console.log('ℹ️  User has no active tours - returning empty dataset');
        return res.json({
          timestamp: now.toISOString(),
          pushSuccess: pushPhaseError === null,
          pushError: pushPhaseError,
          tours: [],
          allTourIds: []
        });
      }

      console.log(`📡 Fetching data for tours: ${tourIds.slice(0, 3).join(', ')}${tourIds.length > 3 ? '...' : ''}`);

      // Fetch related data - using Op.in for array filtering
      console.log('⏳ Querying expenses, settlements, incomes, members...');
      const [expenses, settlements, incomes, joinRequests, members, tours] = await Promise.all([
        Expense.findAll({ 
          where: { tour_id: { [Op.in]: tourIds } },
          raw: true
        }),
        Settlement.findAll({ 
          where: { tour_id: { [Op.in]: tourIds } },
          raw: true
        }),
        ProgramIncome.findAll({ 
          where: { tour_id: { [Op.in]: tourIds } },
          raw: true
        }),
        JoinRequest.findAll({ 
          where: { tour_id: { [Op.in]: tourIds } },
          raw: true
        }),
        TourMember.findAll({ 
          where: { tour_id: { [Op.in]: tourIds } },
          include: [{ model: User, attributes: { exclude: ['password'] } }],
          raw: false
        }),
        Tour.findAll({ 
          where: { id: { [Op.in]: tourIds } },
          raw: true
        })
      ]);
      console.log(`✅ Data fetched - Expenses: ${expenses.length}, Settlements: ${settlements.length}, Members: ${members.length}, Tours: ${tours.length}`);

      // Reconstruct nested structure
      console.log('🔄 Reconstructing tour data...');
      const toursData = tours.map(tour => {
        const tourExpenses = expenses.filter(e => e.tour_id === tour.id);
        const tourMembers = members
          .filter(m => m.tour_id === tour.id)
          .map(m => {
            const plain = m.get({ plain: true });
            const userObj = plain.User;
            delete plain.User;
            return { ...userObj, TourMember: plain };
          });

        return {
          ...tour,
          Expenses: tourExpenses,
          Settlements: settlements.filter(s => s.tour_id === tour.id),
          ProgramIncomes: incomes.filter(i => i.tour_id === tour.id),
          JoinRequests: joinRequests.filter(jr => jr.tour_id === tour.id),
          Users: tourMembers
        };
      });
      console.log(`✅ Reconstructed ${toursData.length} tours with nested data`);

      console.log('📤 Sending response...');
      res.json({
        timestamp: now.toISOString(),
        pushSuccess: pushPhaseError === null,
        pushError: pushPhaseError,
        tours: toursData,
        allTourIds: tourIds
      });
      console.log('✅ Response sent - SYNC COMPLETE');

    } catch (pullErr) {
      console.error('❌ PULL phase error:', {
        message: pullErr.message,
        type: pullErr.constructor.name,
        code: pullErr.code,
        sql: pullErr.sql
      });
      throw pullErr; // Re-throw to outer catch
    }

  } catch (err) {
    console.error('❌ SYNC FAILED - OUTER CATCH:', {
      message: err.message,
      stack: err.stack,
      code: err.code,
      sql: err.sql,
      type: err.constructor.name
    });
    
    if (transaction) {
      try { 
        await transaction.rollback();
      } catch(rbErr) { 
        console.error('⚠️ Final rollback failed:', rbErr.message);
      }
    }

    res.status(500).json({ 
      error: "Sync failed", 
      message: err.message,
      details: err.sql || err.code || '',
      type: err.constructor.name
    });
  }
};
