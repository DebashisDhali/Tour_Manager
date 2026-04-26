const { Tour, User, Expense, ExpenseSplit, ExpensePayer, Settlement, ProgramIncome, TourMember, JoinRequest, sequelize } = require('../models');
const { Op } = require('sequelize');

exports.syncData = async (req, res) => {
  let pushPhaseError = null;

  try {
    console.log('=== 🚀 SYNC START ===');
    const { userId, unsyncedData, lastSync } = req.body;
    
    if (!userId) {
      console.warn('⚠️ userId is missing');
      return res.status(400).json({ error: "userId is required" });
    }

    const normalizedUserId = userId.toLowerCase();
    const now = new Date();
    const lastSyncDate = lastSync ? new Date(lastSync) : new Date(0);
    console.log(`📍 User: ${normalizedUserId} | 🕐 ${now.toISOString()} | 🕒 Last Sync: ${lastSyncDate.toISOString()}`);

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
        
        // --- SECURE SYNC: Fetch User Roles ---
        const myMemberships = await TourMember.findAll({
          where: { user_id: normalizedUserId, status: 'active' },
          attributes: ['tour_id', 'role'],
          raw: true
        });
        const roleMap = {};
        myMemberships.forEach(m => roleMap[m.tour_id.toLowerCase()] = m.role.toLowerCase());
        // ------------------------------------

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
                  avatar_url: u.avatar_url || u.avatarUrl
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
              const tourId = t.id.toLowerCase();
              const role = roleMap[tourId] || 'none';

              if (t.isDeleted) {
                // Security Guard: Only the creator can destroy/soft-delete the actual tour record
                const existingTour = await Tour.findByPk(tourId);
                if (existingTour && existingTour.created_by.toLowerCase() === normalizedUserId) {
                  await Tour.update({ is_deleted: true, updated_at: now }, { where: { id: tourId } });
                  console.log(`    🗑️  Tour ${t.id} soft-deleted by creator`);
                } else {
                  // If not creator, just remove this user's membership (Left the tour)
                  await TourMember.update({ status: 'removed', removed_at: now, updated_at: now }, { 
                    where: { tour_id: tourId, user_id: normalizedUserId } 
                  });
                  console.log(`    🚶 User ${normalizedUserId} left tour ${t.id}`);
                }
              } else {
                const creatorId = (t.created_by || t.createdBy) ? (t.created_by || t.createdBy).toLowerCase() : null;
                
                // If tour exists and user is not Admin/Editor, block update
                const existingTour = await Tour.findByPk(tourId);
                if (existingTour && role !== 'admin' && role !== 'editor') {
                  throw new Error("Permission denied: Viewer cannot edit tour details");
                }

                if (creatorId) {
                  await User.findOrCreate({
                    where: { id: creatorId },
                    defaults: { id: creatorId, name: 'Cloud User' }
                  });
                }

                await Tour.upsert({
                  id: tourId, name: t.name, created_by: creatorId,
                  invite_code: t.invite_code || t.inviteCode || null, 
                  start_date: t.start_date || t.startDate || null,
                  end_date: t.end_date || t.endDate || null, 
                  purpose: t.purpose || 'tour',
                });

                if (creatorId) {
                  await TourMember.upsert({ 
                    tour_id: tourId, user_id: creatorId, 
                    status: 'active', role: 'admin', joined_at: t.startDate || now,
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
              const tourId = (m.tour_id || m.tourId).toLowerCase();
              const mUserId = (m.user_id || m.userId).toLowerCase();
              if (m.isDeleted) {
                await TourMember.destroy({ 
                  where: { tour_id: tourId, user_id: mUserId } 
                });
              } else {
                await TourMember.upsert({
                  tour_id: tourId, user_id: mUserId,
                  status: m.status || (m.left_at || m.leftAt ? 'removed' : 'active'),
                  removed_at: m.left_at || m.leftAt || null, role: m.role || 'viewer',
                  meal_count: m.meal_count || m.mealCount || 0.0,
                  joined_at: now,
                });
              }
            } catch (e) { recordPushError('Member', `${m.tourId}-${m.userId}`, e); }
          }
        }

          // Process expenses
          if (expenses?.length > 0) {
            console.log(`  💰 ${expenses.length} expense(s)`);
            for (const e of expenses) {
              try {
                const tourId = (e.tour_id || e.tourId).toLowerCase();
                const role = roleMap[tourId] || 'none';
                if (role !== 'admin' && role !== 'editor') throw new Error("Permission Denied: Only Admin or Editor can modify expenses");

                if (e.isDeleted) {
                  await Expense.update({ is_deleted: true, updated_at: now }, { where: { id: e.id.toLowerCase() } });
                } else {
                  await Expense.upsert({
                    id: e.id.toLowerCase(), 
                    tour_id: tourId, 
                    payer_id: (e.payer_id || e.payerId) ? (e.payer_id || e.payerId).toLowerCase() : null, 
                    amount: e.amount,
                    title: e.title, category: e.category, 
                    mess_cost_type: e.mess_cost_type || e.messCostType, 
                    date: e.date || e.createdAt || now
                  });
                }
              } catch (err) { recordPushError('Expense', e.id, err); }
            }
          }

          // Process splits
          if (splits?.length > 0) {
            console.log(`  ✂️  ${splits.length} split(s)`);
            const toDelete = splits.filter(s => s.isDeleted).map(s => s.id.toLowerCase());
            if (toDelete.length > 0) await ExpenseSplit.update({ is_deleted: true, updated_at: now }, { where: { id: toDelete } });
            
            for (const s of splits.filter(s => !s.isDeleted)) {
              try {
                await ExpenseSplit.upsert({
                  id: s.id.toLowerCase(), 
                  expense_id: (s.expense_id || s.expenseId).toLowerCase(), 
                  user_id: (s.user_id || s.userId).toLowerCase(), 
                  amount: s.amount
                });
              } catch (err) { recordPushError('Split', s.id, err); }
            }
          }

          // Process payers
          if (payers?.length > 0) {
            console.log(`  💳 ${payers.length} payer(s)`);
            const toDelete = payers.filter(p => p.isDeleted).map(p => p.id.toLowerCase());
            if (toDelete.length > 0) await ExpensePayer.update({ is_deleted: true, updated_at: now }, { where: { id: toDelete } });
            
            for (const p of payers.filter(p => !p.isDeleted)) {
              try {
                await ExpensePayer.upsert({
                  id: p.id.toLowerCase(), 
                  expense_id: (p.expense_id || p.expenseId).toLowerCase(), 
                  user_id: (p.user_id || p.userId).toLowerCase(), 
                  amount: p.amount
                });
              } catch (err) { recordPushError('Payer', p.id, err); }
            }
          }

          // Process settlements
          if (settlements?.length > 0) {
            console.log(`  🤝 ${settlements.length} settlement(s)`);
            for (const s of settlements) {
              try {
                const tourId = s.tourId.toLowerCase();
                const role = roleMap[tourId] || 'none';
                if (role !== 'admin' && role !== 'editor') throw new Error("Permission Denied");

                if (s.isDeleted) {
                  await Settlement.update({ is_deleted: true, updated_at: now }, { where: { id: s.id.toLowerCase() } });
                } else {
                  const tourId = (s.tour_id || s.tourId).toLowerCase();
                  await Settlement.upsert({
                    id: s.id.toLowerCase(), 
                    tour_id: tourId, 
                    from_id: (s.from_id || s.fromId).toLowerCase(), 
                    to_id: (s.to_id || s.toId).toLowerCase(), 
                    amount: s.amount, date: s.date || now
                  });
                }
              } catch (err) { recordPushError('Settlement', s.id, err); }
            }
          }

          // Process incomes
          if (incomes?.length > 0) {
            console.log(`  💵 ${incomes.length} income(s)`);
            for (const i of incomes) {
              try {
                const tourId = i.tourId.toLowerCase();
                const role = roleMap[tourId] || 'none';
                if (role !== 'admin' && role !== 'editor') throw new Error("Permission Denied");

                if (i.isDeleted) {
                  await ProgramIncome.update({ is_deleted: true, updated_at: now }, { where: { id: i.id.toLowerCase() } });
                } else {
                  const tourId = (i.tour_id || i.tourId).toLowerCase();
                  await ProgramIncome.upsert({
                    id: i.id.toLowerCase(), 
                    tour_id: tourId, 
                    amount: i.amount, source: i.source,
                    description: i.description, 
                    collected_by: (i.collected_by || i.collectedBy).toLowerCase(), 
                    date: i.date || now
                  });
                }
              } catch (err) { recordPushError('Income', i.id, err); }
            }
          }

          // Process join requests
          if (joinRequests?.length > 0) {
            console.log(`  📋 ${joinRequests.length} join request(s)`);
            const toDelete = joinRequests.filter(jr => jr.isDeleted).map(jr => jr.id.toLowerCase());
            if (toDelete.length > 0) await JoinRequest.destroy({ where: { id: toDelete } }); // JoinRequest doesn't need soft-delete as it's not part of balance logic
            
            for (const jr of joinRequests.filter(jr => !jr.isDeleted)) {
              try {
                await JoinRequest.upsert({
                  id: jr.id.toLowerCase(), 
                  tour_id: (jr.tour_id || jr.tourId).toLowerCase(), 
                  user_id: (jr.user_id || jr.userId).toLowerCase(), 
                  user_name: jr.user_name || jr.userName || 'Unknown', 
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
        const existing = await TourMember.findOne({
          where: { tour_id: ot.id, user_id: normalizedUserId }
        });
        
        if (!existing || existing.role !== 'admin' || existing.status !== 'active' || existing.removed_at !== null) {
          await TourMember.upsert({
            tour_id: ot.id,
            user_id: normalizedUserId,
            status: 'active',
            role: 'admin',
            removed_at: null,
            joined_at: now,
          });
        }
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

    // Identify tours where the user's membership is "New" or changed since lastSync
    // For these tours, we must do a FULL PULL regardless of lastSyncDate to ensure they have all history.
    const changedMembers = await TourMember.findAll({
      where: { 
        user_id: normalizedUserId, 
        status: 'active',
        updated_at: { [Op.gt]: lastSyncDate }
      },
      attributes: ['tour_id'],
      raw: true
    });
    const fullPullTourIds = new Set(changedMembers.map(m => m.tour_id));

    console.log(`✅ Found ${tourIds.length} active tours (${fullPullTourIds.size} require full sync)`);

    if (tourIds.length === 0) {
      return res.json({
        timestamp: now.toISOString(),
        pushSuccess: pushPhaseError === null,
        pushError: pushPhaseError,
        tours: [],
        allTourIds: []
      });
    }

    // Fetch all data in parallel with incremental filtering
    console.log('⏳ Fetching data modified since:', lastSyncDate.toISOString());
    const [tours, expenses, splits, payers, settlements, incomes, joinRequests, members] = await Promise.all([
      Tour.findAll({ 
        where: { 
          id: { [Op.in]: tourIds }, 
          [Op.or]: [
            { id: { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      Expense.findAll({ 
        where: { 
          tour_id: { [Op.in]: tourIds }, 
          [Op.or]: [
            { tour_id: { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      ExpenseSplit.findAll({ 
        include: [{
          model: Expense,
          where: { tour_id: { [Op.in]: tourIds } },
          attributes: []
        }],
        where: { 
          [Op.or]: [
            { '$Expense.tour_id$': { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      ExpensePayer.findAll({ 
        include: [{
          model: Expense,
          where: { tour_id: { [Op.in]: tourIds } },
          attributes: []
        }],
        where: { 
          [Op.or]: [
            { '$Expense.tour_id$': { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      Settlement.findAll({ 
        where: { 
          tour_id: { [Op.in]: tourIds }, 
          [Op.or]: [
            { tour_id: { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      ProgramIncome.findAll({ 
        where: { 
          tour_id: { [Op.in]: tourIds }, 
          [Op.or]: [
            { tour_id: { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      JoinRequest.findAll({ 
        where: { 
          tour_id: { [Op.in]: tourIds }, 
          [Op.or]: [
            { tour_id: { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        }, 
        raw: true 
      }),
      TourMember.findAll({ 
        where: { 
          tour_id: { [Op.in]: tourIds }, 
          [Op.or]: [
            { tour_id: { [Op.in]: Array.from(fullPullTourIds) } },
            { updated_at: { [Op.gt]: lastSyncDate } }
          ]
        },
        include: [{ model: User, attributes: { exclude: ['password'] } }]
      })
    ]);
    console.log(`✅ Data fetched. T:${tours.length} E:${expenses.length} S:${splits.length} P:${payers.length}`);

    // Map changed records to their respective tours
    // We need to include ANY tour that has ANY changed sub-record, OR itself changed.
    const impactedTourIds = new Set([
      ...tours.map(t => t.id.toLowerCase()),
      ...expenses.map(e => e.tour_id.toLowerCase()),
      ...settlements.map(s => s.tour_id.toLowerCase()),
      ...incomes.map(i => i.tour_id.toLowerCase()),
      ...joinRequests.map(jr => jr.tour_id.toLowerCase()),
      ...members.map(m => m.tour_id.toLowerCase())
    ]);

    // For impacted tours where the tour record ITSELF didn't change, we still need to provide the tour object skeleton
    // so the client can correctly group the sub-records under it.
    const additionalToursNeeded = Array.from(impactedTourIds).filter(id => !tours.find(t => t.id.toLowerCase() === id));
    let baseTours = [...tours];
    if (additionalToursNeeded.length > 0) {
      const extraTours = await Tour.findAll({ where: { id: { [Op.in]: additionalToursNeeded } }, raw: true });
      baseTours = [...baseTours, ...extraTours];
    }

    // Reconstruct with explicit mapping to camelCase for Flutter compatibility
    const toursData = baseTours.map(tour => {
      const tourIdLower = tour.id.toLowerCase();
      
      const tourExpenses = expenses.filter(e => e.tour_id.toLowerCase() === tourIdLower);
      const tourExpensesWithDetails = tourExpenses.map(e => {
        const expenseIdLower = e.id.toLowerCase();
        return {
          id: e.id,
          tourId: e.tour_id.toLowerCase(),
          payerId: e.payer_id ? e.payer_id.toLowerCase() : null,
          amount: parseFloat(e.amount),
          title: e.title,
          category: e.category,
          messCostType: e.mess_cost_type,
          createdAt: e.date,
          updatedAt: e.updated_at,
          ExpenseSplits: splits
            .filter(s => s.expense_id.toLowerCase() === expenseIdLower)
            .map(s => ({
              id: s.id,
              user_id: s.user_id.toLowerCase(),
              amount: parseFloat(s.amount),
              updatedAt: s.updated_at
            })),
          ExpensePayers: payers
            .filter(p => p.expense_id.toLowerCase() === expenseIdLower)
            .map(p => ({
              id: p.id,
              user_id: p.user_id.toLowerCase(),
              amount: parseFloat(p.amount),
              updatedAt: p.updated_at
            }))
        };
      });

      // Also gather orphaned splits/payers (where split changed but expense didn't)
      // We'll attach them to "dummy" expense objects or find the parent expense.
      // But wait! If a split changed, we should ideally have bumped the expense's updated_at.
      // Let's check if there are any splits whose expense isn't and won't be in the list.
      const existingExpenseIds = new Set(tourExpensesWithDetails.map(e => e.id.toLowerCase()));
      const orphanedSplits = splits.filter(s => {
        // Need to find which tour this split belongs to... this is expensive.
        // Simplified: the query for splits already filtered by the accessible tourIds.
        // We just need to find if its expense is already in tourExpensesWithDetails.
        return !existingExpenseIds.has(s.expense_id.toLowerCase());
      });
      
      // For orphaned splits, we should ideally fetch their parent expenses too.
      // To keep it simple and performant, we'll suggest that any change to a split/payer MUST bump the expense updated_at.
      // (I'll implement a hook or manual update for this).

      return {
        id: tour.id.toLowerCase(),
        name: tour.name,
        startDate: tour.start_date,
        endDate: tour.end_date,
        inviteCode: tour.invite_code,
        createdBy: tour.created_by.toLowerCase(),
        purpose: tour.purpose || 'tour',
        status: tour.status || 'active',
        updatedAt: tour.updated_at,
        
        Expenses: tourExpensesWithDetails,
        
        Settlements: settlements
          .filter(s => s.tour_id.toLowerCase() === tourIdLower)
          .map(s => ({
            id: s.id,
            tourId: s.tour_id.toLowerCase(),
            fromId: s.from_id.toLowerCase(),
            toId: s.to_id.toLowerCase(),
            amount: parseFloat(s.amount),
            date: s.date,
            updatedAt: s.updated_at
          })),
          
        ProgramIncomes: incomes
          .filter(i => i.tour_id.toLowerCase() === tourIdLower)
          .map(i => ({
            id: i.id,
            tourId: i.tour_id.toLowerCase(),
            amount: parseFloat(i.amount),
            source: i.source,
            description: i.description,
            collectedBy: i.collected_by.toLowerCase(),
            date: i.date,
            updatedAt: i.updated_at
          })),

        JoinRequests: joinRequests
          .filter(jr => jr.tour_id.toLowerCase() === tourIdLower)
          .map(jr => ({
            id: jr.id,
            tourId: jr.tour_id.toLowerCase(),
            userId: jr.user_id.toLowerCase(),
            userName: jr.userName,
            status: jr.status,
            updatedAt: jr.updated_at
          })),

        Users: members
          .filter(m => m.tour_id.toLowerCase() === tourIdLower)
          .map(m => {
            const plain = m.get({ plain: true });
            const userObj = plain.User;
            return {
              id: userObj.id.toLowerCase(),
              name: userObj.name,
              email: userObj.email,
              phone: userObj.phone,
              avatarUrl: userObj.avatar_url,
              purpose: userObj.purpose,
              TourMember: {
                tourId: plain.tour_id.toLowerCase(),
                userId: plain.user_id.toLowerCase(),
                role: plain.role,
                status: plain.status,
                joinedAt: plain.joined_at,
                removedAt: plain.removed_at,
                mealCount: parseFloat(plain.meal_count || 0),
                updatedAt: plain.updated_at
              }
            };
          })
      };
    });

    console.log(`✅ SYNC COMPLETE: ${toursData.length} tours synced incrementally`);
    res.json({
      timestamp: now.toISOString(),
      pushSuccess: pushPhaseError === null,
      pushError: pushPhaseError,
      tours: toursData,
      allTourIds: tourIds.map(id => id.toLowerCase())
    });

  } catch (err) {
    console.error('❌ SYNC FAILED:', err);
    res.status(500).json({ 
      error: "Sync failed", 
      message: err.message
    });
  }
};
