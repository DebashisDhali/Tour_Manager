const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, JoinRequest, sequelize } = require('../models');
const { Op } = require('sequelize');

exports.syncData = async (req, res) => {
  let pushPhaseError = null;

  try {
    console.log('=== 🚀 SYNC START ===');
    const { userId, unsyncedData } = req.body;
    
    if (!userId) {
      console.warn('⚠️ userId is missing');
      return res.status(400).json({ error: "userId is required" });
    }

    const normalizedUserId = userId.toLowerCase();
    const now = new Date();
    console.log(`📍 User: ${normalizedUserId} | 🕐 ${now.toISOString()}`);

    // ========== PUSH PHASE (NO TRANSACTION) ==========
    console.log('📤 Starting PUSH phase...');
    try {
      // Ensure user exists
      let user = await User.findByPk(normalizedUserId);
      if (!user) {
        console.log(`👤 Creating user: ${normalizedUserId}`);
        await User.create({ id: normalizedUserId, name: 'Mobile User' });
      } else {
        await User.update({ is_registered: true }, { where: { id: normalizedUserId } });
      }

      if (unsyncedData) {
        const pushItemErrors = [];
        const recordPushError = (scope, id, error) => {
          const msg = `${scope}[${id}]: ${error?.message || error}`;
          pushItemErrors.push(msg);
          console.error(`    ⚠️ ${msg}`);
        };
        const { tours, users, expenses, splits, payers, settlements, incomes, members, joinRequests } = unsyncedData;

        // Process users
        if (users?.length > 0) {
          console.log(`  👥 ${users.length} user(s)`);
          for (const u of users) {
            try {
              if (u.isDeleted) {
                await User.destroy({ where: { id: u.id.toLowerCase() } });
              } else {
                await User.upsert({
                  id: u.id.toLowerCase(), name: u.name, phone: u.phone, email: u.email,
                  avatar_url: u.avatarUrl
                });
              }
            } catch (e) { recordPushError('User', u.id, e); }
          }
        }

        // Process tours
        if (tours?.length > 0) {
          console.log(`  🏕️  ${tours.length} tour(s)`);
          for (const t of tours) {
            try {
              if (t.isDeleted) {
                await Tour.destroy({ where: { id: t.id.toLowerCase() } });
              } else {
                const creatorId = t.createdBy ? t.createdBy.toLowerCase() : null;
                
                if (creatorId) {
                  await User.findOrCreate({
                    where: { id: creatorId },
                    defaults: { id: creatorId, name: 'Cloud User' }
                  });
                }

                await Tour.upsert({
                  id: t.id.toLowerCase(), name: t.name, created_by: creatorId,
                  invite_code: t.inviteCode || null, start_date: t.startDate || null,
                  end_date: t.endDate || null, purpose: t.purpose || 'tour',
                  created_at: now,
                  updated_at: now
                });

                if (creatorId) {
                  await TourMember.upsert({ 
                    tour_id: t.id.toLowerCase(), user_id: creatorId, 
                    status: 'active', role: 'admin', joined_at: t.startDate || now,
                    created_at: now,
                    updated_at: now,
                  });
                }
              }
            } catch (e) { recordPushError('Tour', t.id, e); }
          }
        }

        // Process members
        if (members?.length > 0) {
          console.log(`  👫 ${members.length} member(s)`);
          for (const m of members) {
            try {
              if (m.isDeleted) {
                await TourMember.destroy({ 
                  where: { tour_id: m.tourId.toLowerCase(), user_id: m.userId.toLowerCase() } 
                });
              } else {
                await TourMember.upsert({
                  tour_id: m.tourId.toLowerCase(), user_id: m.userId.toLowerCase(),
                  status: m.status || (m.leftAt ? 'removed' : 'active'),
                  removed_at: m.leftAt || null, role: m.role || 'viewer',
                  meal_count: m.mealCount || 0.0,
                  joined_at: now,
                  created_at: now,
                  updated_at: now,
                });
              }
            } catch (e) { recordPushError('Member', `${m.tourId}-${m.userId}`, e); }
          }
        }

          // Process expenses
          if (expenses?.length > 0) {
            console.log(`  💰 ${expenses.length} expense(s)`);
            const toDelete = expenses.filter(e => e.isDeleted).map(e => e.id.toLowerCase());
            if (toDelete.length > 0) await Expense.destroy({ where: { id: toDelete } });
            
            for (const e of expenses.filter(e => !e.isDeleted)) {
              try {
                await Expense.upsert({
                  id: e.id.toLowerCase(), 
                  tour_id: e.tourId.toLowerCase(), 
                  payer_id: e.payerId ? e.payerId.toLowerCase() : null, 
                  amount: e.amount,
                  title: e.title, category: e.category, mess_cost_type: e.messCostType, 
                  date: e.createdAt || now
                });
              } catch (err) { recordPushError('Expense', e.id, err); }
            }
          }

          // Process splits
          if (splits?.length > 0) {
            console.log(`  ✂️  ${splits.length} split(s)`);
            const toDelete = splits.filter(s => s.isDeleted).map(s => s.id.toLowerCase());
            if (toDelete.length > 0) await ExpenseSplit.destroy({ where: { id: toDelete } });
            
            for (const s of splits.filter(s => !s.isDeleted)) {
              try {
                await ExpenseSplit.upsert({
                  id: s.id.toLowerCase(), 
                  expense_id: s.expenseId.toLowerCase(), 
                  user_id: s.userId.toLowerCase(), 
                  amount: s.amount
                });
              } catch (err) { recordPushError('Split', s.id, err); }
            }
          }

          // Process payers
          if (payers?.length > 0) {
            console.log(`  💳 ${payers.length} payer(s)`);
            const toDelete = payers.filter(p => p.isDeleted).map(p => p.id.toLowerCase());
            if (toDelete.length > 0) await ExpensePayer.destroy({ where: { id: toDelete } });
            
            for (const p of payers.filter(p => !p.isDeleted)) {
              try {
                await ExpensePayer.upsert({
                  id: p.id.toLowerCase(), 
                  expense_id: p.expenseId.toLowerCase(), 
                  user_id: p.userId.toLowerCase(), 
                  amount: p.amount
                });
              } catch (err) { recordPushError('Payer', p.id, err); }
            }
          }

          // Process settlements
          if (settlements?.length > 0) {
            console.log(`  🤝 ${settlements.length} settlement(s)`);
            const toDelete = settlements.filter(s => s.isDeleted).map(s => s.id.toLowerCase());
            if (toDelete.length > 0) await Settlement.destroy({ where: { id: toDelete } });
            
            for (const s of settlements.filter(s => !s.isDeleted)) {
              try {
                await Settlement.upsert({
                  id: s.id.toLowerCase(), 
                  tour_id: s.tourId.toLowerCase(), 
                  from_id: s.fromId.toLowerCase(), 
                  to_id: s.toId.toLowerCase(), 
                  amount: s.amount, date: s.date || now
                });
              } catch (err) { recordPushError('Settlement', s.id, err); }
            }
          }

          // Process incomes
          if (incomes?.length > 0) {
            console.log(`  💵 ${incomes.length} income(s)`);
            const toDelete = incomes.filter(i => i.isDeleted).map(i => i.id.toLowerCase());
            if (toDelete.length > 0) await ProgramIncome.destroy({ where: { id: toDelete } });
            
            for (const i of incomes.filter(i => !i.isDeleted)) {
              try {
                await ProgramIncome.upsert({
                  id: i.id.toLowerCase(), 
                  tour_id: i.tourId.toLowerCase(), 
                  amount: i.amount, source: i.source,
                  description: i.description, 
                  collected_by: i.collectedBy.toLowerCase(), 
                  date: i.date || now
                });
              } catch (err) { recordPushError('Income', i.id, err); }
            }
          }

          // Process join requests
          if (joinRequests?.length > 0) {
            console.log(`  📋 ${joinRequests.length} join request(s)`);
            const toDelete = joinRequests.filter(jr => jr.isDeleted).map(jr => jr.id.toLowerCase());
            if (toDelete.length > 0) await JoinRequest.destroy({ where: { id: toDelete } });
            
            for (const jr of joinRequests.filter(jr => !jr.isDeleted)) {
              try {
                await JoinRequest.upsert({
                  id: jr.id.toLowerCase(), 
                  tour_id: jr.tourId.toLowerCase(), 
                  user_id: jr.userId.toLowerCase(), 
                  user_name: jr.userName || 'Unknown', 
                  status: jr.status || 'pending'
                });
              } catch (err) { recordPushError('JoinRequest', jr.id, err); }
            }
          }

        if (pushItemErrors.length > 0) {
          throw new Error(`Push item failures: ${pushItemErrors.slice(0, 3).join(' | ')}`);
        }
      }

      // Self-heal guard: creator must always be an active admin member in own tours.
      const ownedTours = await Tour.findAll({
        where: { created_by: normalizedUserId },
        attributes: ['id'],
        raw: true,
      });
      for (const ot of ownedTours) {
        await TourMember.upsert({
          tour_id: ot.id,
          user_id: normalizedUserId,
          status: 'active',
          role: 'admin',
          removed_at: null,
          joined_at: now,
          created_at: now,
          updated_at: now,
        });
      }

      console.log('✅ PUSH phase done');
    } catch (pushErr) {
      console.error('⚠️ PUSH error:', pushErr.message);
      pushPhaseError = pushErr.message;
    }

    // ========== PULL PHASE ==========
    console.log('📥 Starting PULL phase...');
    
    const activeTourRecords = await TourMember.findAll({
      where: { user_id: normalizedUserId, status: 'active' },
      attributes: ['tour_id'],
      raw: true
    });

    const ownerTourRecords = await Tour.findAll({
      where: { created_by: normalizedUserId },
      attributes: ['id'],
      raw: true,
    });

    const tourIds = Array.from(
      new Set([
        ...activeTourRecords.map(r => r.tour_id),
        ...ownerTourRecords.map(r => r.id),
      ])
    );
    console.log(`✅ Found ${tourIds.length} active tours`);

    if (tourIds.length === 0) {
      return res.json({
        timestamp: now.toISOString(),
        pushSuccess: pushPhaseError === null,
        pushError: pushPhaseError,
        tours: [],
        allTourIds: []
      });
    }

    // Fetch all data in parallel
    console.log('⏳ Fetching data...');
    const [tours, expenses, settlements, incomes, joinRequests, members] = await Promise.all([
      Tour.findAll({ where: { id: { [Op.in]: tourIds } }, raw: true }),
      Expense.findAll({ where: { tour_id: { [Op.in]: tourIds } }, raw: true }),
      Settlement.findAll({ where: { tour_id: { [Op.in]: tourIds } }, raw: true }),
      ProgramIncome.findAll({ where: { tour_id: { [Op.in]: tourIds } }, raw: true }),
      JoinRequest.findAll({ where: { tour_id: { [Op.in]: tourIds } }, raw: true }),
      TourMember.findAll({ 
        where: { tour_id: { [Op.in]: tourIds } },
        include: [{ model: User, attributes: { exclude: ['password'] } }]
      })
    ]);
    console.log(`✅ Data fetched`);

    // Reconstruct with case-insensitive filtering for robustness
    const toursData = tours.map(tour => {
      const tourIdLower = tour.id.toLowerCase();
      return {
        ...tour,
        Expenses: expenses.filter(e => e.tour_id.toLowerCase() === tourIdLower),
        Settlements: settlements.filter(s => s.tour_id.toLowerCase() === tourIdLower),
        ProgramIncomes: incomes.filter(i => i.tour_id.toLowerCase() === tourIdLower),
        JoinRequests: joinRequests.filter(jr => jr.tour_id.toLowerCase() === tourIdLower),
        Users: members
          .filter(m => m.tour_id.toLowerCase() === tourIdLower)
          .map(m => {
            const plain = m.get({ plain: true });
            const userObj = plain.User;
            delete plain.User;
            return { ...userObj, TourMember: plain };
          })
      };
    });

    console.log(`✅ SYNC COMPLETE`);
    res.json({
      timestamp: now.toISOString(),
      pushSuccess: pushPhaseError === null,
      pushError: pushPhaseError,
      tours: toursData,
      allTourIds: tourIds
    });

  } catch (err) {
    console.error('❌ SYNC FAILED:', err.message);
    res.status(500).json({ 
      error: "Sync failed", 
      message: err.message
    });
  }
};
