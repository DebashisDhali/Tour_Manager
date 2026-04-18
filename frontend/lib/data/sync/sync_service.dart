import 'dart:async';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import 'package:uuid/uuid.dart';

class SyncService {
  final AppDatabase db;
  final Dio dio;
  final String baseUrl;

  SyncService(this.db, this.dio, this.baseUrl) {
    print("📡 SyncService initialized with BaseURL: $baseUrl");
  }

  Map<String, dynamic>? _memberMeta(dynamic user) {
    if (user is! Map) return null;
    final meta =
        user['TourMember'] ?? user['tourMember'] ?? user['tour_member'];
    return meta is Map<String, dynamic> ? meta : null;
  }

  String _normalizeRole(dynamic role) {
    final r = role?.toString().toLowerCase().trim() ?? 'viewer';
    if (r == 'admin' || r == 'editor' || r == 'viewer') return r;
    return 'viewer';
  }

  String _normalizeStatus(dynamic status, dynamic removedAt) {
    final s = status?.toString().toLowerCase().trim() ?? '';
    if (s == 'active' || s == 'pending' || s == 'removed') return s;
    return removedAt != null ? 'removed' : 'active';
  }

  Future<void> startSync(String userId) async {
    try {
      print("Sync started for user: $userId");

      final lastSync = await db.getSyncMetadata('last_sync_$userId');

      // 1. Gather Unsynced Data in Parallel
      final results = await Future.wait([
        db.getUnsyncedUsers(),
        db.getUnsyncedTours(),
        db.getUnsyncedExpenses(),
        db.getUnsyncedSplits(),
        db.getUnsyncedExpensePayers(),
        db.getUnsyncedTourMembers(),
        db.getUnsyncedSettlements(),
        db.getUnsyncedProgramIncomes(),
        db.getUnsyncedJoinRequests(),
      ]);

      final unsyncedUsers = results[0] as List<User>;
      final unsyncedTours = results[1] as List<Tour>;
      final unsyncedExpenses = results[2] as List<Expense>;
      final unsyncedSplits = results[3] as List<ExpenseSplit>;
      final unsyncedPayers = results[4] as List<ExpensePayer>;
      final unsyncedMembers = results[5] as List<TourMember>;
      final unsyncedSettlements = results[6] as List<Settlement>;
      final unsyncedIncomes = results[7] as List<ProgramIncome>;
      final unsyncedJoinRequests = results[8] as List<JoinRequest>;

      final response = await dio.post('$baseUrl/sync', data: {
        'userId': userId,
        'lastSync': lastSync,
        'unsyncedData': {
          'users': unsyncedUsers
              .map((u) => {
                    'id': u.id,
                    'name': u.name,
                    'phone': u.phone,
                    'email': u.email,
                    'avatarUrl': u.avatarUrl,
                    'purpose': u.purpose
                  })
              .toList(),
          'tours': unsyncedTours
              .map((t) => {
                    'id': t.id,
                    'name': t.name,
                    'createdBy': t.createdBy,
                    'inviteCode': t.inviteCode,
                    'startDate': t.startDate?.toIso8601String(),
                    'endDate': t.endDate?.toIso8601String(),
                    'purpose': t.purpose,
                    'isDeleted': t.isDeleted,
                  })
              .toList(),
          'expenses': unsyncedExpenses
              .map((e) => {
                    'id': e.id,
                    'tourId': e.tourId,
                    'payerId': e.payerId,
                    'amount': e.amount,
                    'title': e.title,
                    'category': e.category,
                    'messCostType': e.messCostType,
                    'createdAt': e.createdAt.toIso8601String(),
                    'isDeleted': e.isDeleted,
                  })
              .toList(),
          'splits': unsyncedSplits
              .map((s) => {
                    'id': s.id,
                    'expenseId': s.expenseId,
                    'userId': s.userId,
                    'amount': s.amount,
                    'isDeleted': s.isDeleted,
                  })
              .toList(),
          'payers': unsyncedPayers
              .map((p) => {
                    'id': p.id,
                    'expenseId': p.expenseId,
                    'userId': p.userId,
                    'amount': p.amount,
                    'isDeleted': p.isDeleted,
                  })
              .toList(),
          'members': unsyncedMembers
              .map((m) => {
                    'tourId': m.tourId,
                    'userId': m.userId,
                    'leftAt': m.leftAt?.toIso8601String(),
                    'mealCount': m.mealCount,
                    'role': m.role,
                    'status': m.status,
                    'isDeleted': m.isDeleted,
                  })
              .toList(),
          'settlements': unsyncedSettlements
              .map((s) => {
                    'id': s.id,
                    'tourId': s.tourId,
                    'fromId': s.fromId,
                    'toId': s.toId,
                    'amount': s.amount,
                    'date': s.date.toIso8601String(),
                    'isDeleted': s.isDeleted,
                  })
              .toList(),
          'incomes': unsyncedIncomes
              .map((i) => {
                    'id': i.id,
                    'tourId': i.tourId,
                    'amount': i.amount,
                    'source': i.source,
                    'description': i.description,
                    'collectedBy': i.collectedBy,
                    'date': i.date.toIso8601String(),
                    'isDeleted': i.isDeleted,
                  })
              .toList(),
          'joinRequests': unsyncedJoinRequests
              .map((jr) => {
                    'id': jr.id,
                    'tourId': jr.tourId,
                    'userId': jr.userId,
                    'userName': jr.userName,
                    'status': jr.status,
                  })
              .toList(),
        }
      });

      if (response.statusCode == 200) {
        final pushSuccess = response.data['pushSuccess'] ?? true;
        if (pushSuccess == false) {
          final pushError = response.data['pushError'] ?? 'Unknown push error';
          print("⚠️ Push failed on server: $pushError");
          throw Exception(
              "Sync partial failure: $pushError. Server prevented local changes from being saved.");
        }

        print("✅ Server returned 200. Marking pushed items as synced.");
        // 2. Mark Pushed data as synced
        await Future.wait([
          for (final u in unsyncedUsers)
            u.isDeleted
                ? db.delete(db.users).delete(u)
                : db.markUserSynced(u.id),
          for (final t in unsyncedTours)
            t.isDeleted
                ? db.hardDeleteTourWithDetails(t.id)
                : db.markTourSynced(t.id),
          for (final m in unsyncedMembers)
            db.markTourMemberSynced(m.tourId, m.userId),
          for (final e in unsyncedExpenses)
            e.isDeleted
                ? db.hardDeleteExpenseWithDetails(e.id)
                : db.markExpenseSynced(e.id),
          for (final s in unsyncedSplits)
            s.isDeleted
                ? db.delete(db.expenseSplits).delete(s)
                : db.markSplitSynced(s.id),
          for (final p in unsyncedPayers)
            p.isDeleted
                ? db.delete(db.expensePayers).delete(p)
                : db.markExpensePayerSynced(p.id),
          for (final s in unsyncedSettlements)
            s.isDeleted
                ? db.hardDeleteSettlement(s.id)
                : db.markSettlementSynced(s.id),
          for (final i in unsyncedIncomes)
            i.isDeleted
                ? db.hardDeleteProgramIncome(i.id)
                : db.markProgramIncomeSynced(i.id),
          for (final jr in unsyncedJoinRequests)
            db.markJoinRequestSynced(jr.id),
        ]);

        print("🔄 Running batch update for server data...");
        // Mark as synced locally & Pulled data within a batch for efficiency
        await db.batch((batch) {
          final serverTours = (response.data['tours'] as List?) ?? [];
          for (final st in serverTours) {
            if (st == null) continue;

            // Sync Join Requests (if returned in tour data or separately)
            final jrList = st['JoinRequests'] ?? st['joinRequests'];
            if (jrList != null && jrList is List) {
              for (final jr in jrList) {
                if (jr == null) continue;
                batch.insert(
                    db.joinRequests,
                    JoinRequestsCompanion.insert(
                      id: jr['id'] ?? '',
                      tourId: st['id'] ?? '',
                      userId: jr['user_id'] ?? '',
                      userName: jr['user_name'] ?? 'User',
                      status: Value(jr['status']),
                      isSynced: const Value(true),
                    ),
                    mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Tour
            final String? inviteCodeValue =
                st.containsKey('invite_code') && st['invite_code'] != null
                    ? st['invite_code'].toString()
                    : null;
            final Value<String?> inviteCodeField = inviteCodeValue != null
                ? Value<String?>(inviteCodeValue)
                : const Value.absent();
            batch.insert(
                db.tours,
                ToursCompanion.insert(
                  id: st['id'] ?? '',
                  name: st['name'] ?? 'Unknown Tour',
                  startDate: Value(st['start_date'] != null
                      ? DateTime.tryParse(st['start_date'].toString())
                      : null),
                  endDate: Value(st['end_date'] != null
                      ? DateTime.tryParse(st['end_date'].toString())
                      : null),
                  inviteCode: inviteCodeField,
                  createdBy: st['created_by'] ?? '',
                  purpose: Value(st['purpose'] ?? 'tour'),
                  isSynced: const Value(true),
                  updatedAt: Value(DateTime.now()),
                ),
                mode: InsertMode.insertOrReplace);

            // Sync Members
            final membersList = st['Users'] ?? st['users'];
            if (membersList != null && membersList is List) {
              for (final su in membersList) {
                if (su == null) continue;
                String userName = (su['name'] ?? 'Unknown').toString();
                final userEmail = su['email']?.toString();

                if ((userName.toLowerCase() == 'unknown' || userName.isEmpty) &&
                    userEmail != null &&
                    userEmail.contains('@')) {
                  final parts = userEmail.split('@');
                  if (parts.isNotEmpty && parts[0].isNotEmpty) {
                    userName =
                        parts[0][0].toUpperCase() + parts[0].substring(1);
                  }
                }

                batch.insert(
                    db.users,
                    UsersCompanion.insert(
                      id: su['id'] ?? '',
                      name: userName,
                      phone: Value(su['phone']),
                      email: Value(userEmail),
                      avatarUrl: Value(su['avatar_url']),
                      purpose: Value(su['purpose']),
                      isMe: Value(su['id'].toString().toLowerCase() ==
                          userId.toLowerCase()),
                      isSynced: const Value(true),
                      updatedAt: Value(DateTime.now()),
                    ),
                    mode: InsertMode.insertOrReplace);

                // Add member connection
                final suMeta = _memberMeta(su);
                final suStatus =
                    _normalizeStatus(suMeta?['status'], suMeta?['removed_at']);
                final suLeftAt = (suMeta?['removed_at'] != null)
                    ? DateTime.tryParse(suMeta?['removed_at'].toString() ?? '')
                    : null;
                final suRole = _normalizeRole(suMeta?['role']);

                batch.insert(
                    db.tourMembers,
                    TourMembersCompanion.insert(
                      tourId: st['id'],
                      userId: su['id'],
                      status: Value(suStatus),
                      leftAt: Value(suLeftAt),
                      role: Value(suRole),
                      mealCount: Value(double.tryParse(
                              su['meal_count']?.toString() ?? '0') ??
                          0.0),
                      isSynced: const Value(true),
                    ),
                    mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Expenses
            if (st['Expenses'] != null) {
              for (final se in st['Expenses']) {
                batch.insert(
                    db.expenses,
                    ExpensesCompanion.insert(
                      id: se['id'],
                      tourId: st['id'],
                      payerId: Value(se['payer_id']),
                      amount:
                          double.tryParse(se['amount']?.toString() ?? '0') ??
                              0.0,
                      title: se['title'],
                      category: (se['category'] ?? 'Others').toString(),
                      messCostType: Value(se['mess_cost_type']),
                      isSynced: const Value(true),
                      createdAt: Value(
                          DateTime.tryParse(se['date']?.toString() ?? '') ??
                              (se['created_at'] != null
                                  ? DateTime.tryParse(
                                          se['created_at'].toString()) ??
                                      DateTime.now()
                                  : DateTime.now())),
                    ),
                    mode: InsertMode.insertOrReplace);

                // Sync Splits
                if (se['ExpenseSplits'] != null) {
                  for (final ss in se['ExpenseSplits']) {
                    batch.insert(
                        db.expenseSplits,
                        ExpenseSplitsCompanion.insert(
                          id: ss['id'] ?? const Uuid().v4(),
                          expenseId: se['id'],
                          userId: ss['user_id'],
                          amount: double.tryParse(
                                  ss['amount']?.toString() ?? '0') ??
                              0.0,
                          isSynced: const Value(true),
                        ),
                        mode: InsertMode.insertOrReplace);
                  }
                }

                // Sync Payers
                if (se['ExpensePayers'] != null) {
                  for (final sp in se['ExpensePayers']) {
                    batch.insert(
                        db.expensePayers,
                        ExpensePayersCompanion.insert(
                          id: sp['id'] ?? const Uuid().v4(),
                          expenseId: se['id'],
                          userId: sp['user_id'],
                          amount: double.tryParse(
                                  sp['amount']?.toString() ?? '0') ??
                              0.0,
                          isSynced: const Value(true),
                        ),
                        mode: InsertMode.insertOrReplace);
                  }
                }
              }
            }

            final settlements = st['Settlements'] ?? st['settlements'];
            if (settlements != null && settlements is List) {
              for (final ss in settlements) {
                final fromId = (ss['from_id'] ?? ss['fromId'] ?? '').toString();
                final toId = (ss['to_id'] ?? ss['toId'] ?? '').toString();
                if (fromId.isEmpty || toId.isEmpty) continue;

                batch.insert(
                    db.settlements,
                    SettlementsCompanion.insert(
                      id: (ss['id'] ?? '').toString(),
                      tourId: (st['id'] ?? '').toString(),
                      fromId: fromId,
                      toId: toId,
                      amount:
                          double.tryParse(ss['amount']?.toString() ?? '0') ??
                              0.0,
                      date: Value(ss['date'] != null
                          ? DateTime.parse(ss['date'].toString())
                          : DateTime.now()),
                      isSynced: const Value(true),
                    ),
                    mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Program Incomes
            final incomes =
                st['ProgramIncomes'] ?? st['programIncomes'] ?? st['incomes'];
            if (incomes != null && incomes is List) {
              for (final inc in incomes) {
                batch.insert(
                    db.programIncomes,
                    ProgramIncomesCompanion.insert(
                      id: (inc['id'] ?? '').toString(),
                      tourId: (st['id'] ?? '').toString(),
                      amount:
                          double.tryParse(inc['amount']?.toString() ?? '0') ??
                              0.0,
                      source: (inc['source'] ?? '').toString(),
                      description: Value((inc['description'] ?? '').toString()),
                      collectedBy:
                          (inc['collected_by'] ?? inc['collectedBy'] ?? '')
                              .toString(),
                      date: Value(inc['date'] != null
                          ? DateTime.parse(inc['date'].toString())
                          : DateTime.now()),
                      isSynced: const Value(true),
                    ),
                    mode: InsertMode.insertOrReplace);
              }
            }
          }
        });

        // Handle Deletions (Membership changes)
        // ONLY delete if we got a valid list of tours back from the server
        final allTourIds = (response.data['allTourIds'] as List?)
            ?.map((id) => id.toString())
            .toSet();
        final lastSyncDate =
            lastSync != null ? DateTime.tryParse(lastSync) : null;
        if (allTourIds != null && allTourIds.isNotEmpty) {
          final serverIdsLower =
              allTourIds.map((id) => id.toString().toLowerCase()).toSet();
          final localTours = await db.select(db.tours).get();
          for (final lt in localTours) {
            final localIdLower = lt.id.toLowerCase();
            final hasStaleServerMembership = lt.isSynced &&
                !serverIdsLower.contains(localIdLower) &&
                lastSyncDate != null &&
                lt.updatedAt != null &&
                lt.updatedAt!.isBefore(lastSyncDate);
            if (hasStaleServerMembership) {
              print(
                  "🗑️ Removing tour ${lt.name} - no longer a member on server");
              await db.deleteTourWithDetails(lt.id);
            } else if (lt.isSynced && !serverIdsLower.contains(localIdLower)) {
              print(
                  "⚠️ Keeping recent tour ${lt.name} because it was updated after last sync and may still be pending on server.");
            }
          }
        }

        if (response.data['timestamp'] != null) {
          await db.setSyncMetadata(
              'last_sync_$userId', response.data['timestamp'].toString());
        }
        print("✅ Sync completed successfully.");
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } on DioException catch (e) {
      String errorMsg = "Sync failed. ";
      if (e.response?.data != null && e.response?.data is Map) {
        final data = e.response!.data as Map;
        errorMsg =
            data['error'] ?? data['message'] ?? e.message ?? "Server Error";
        if (data['details'] != null) errorMsg += ": ${data['details']}";
      } else {
        errorMsg += e.message ?? "Unknown network error";
      }
      print("❌ Sync Engine DioError: $errorMsg");
      throw Exception(errorMsg);
    } catch (e) {
      print("❌ Sync Engine Generic Error: $e");
      rethrow;
    }
  }

  Future<void> joinByInvite(String inviteCode, String userId, String userName,
      {String? email, String? avatarUrl, String? purpose}) async {
    try {
      print("=== JOIN REQUEST START ===");
      print("Invite Code: $inviteCode");
      print("User ID: $userId");
      print("User Name: $userName");

      final response = await dio.post('$baseUrl/tours/join', data: {
        'invite_code': inviteCode,
        'user_id': userId,
        'user_name': userName,
        'email': email,
        'avatar_url': avatarUrl,
        'purpose': purpose
      });

      print("Response Status: ${response.statusCode}");
      print("Response Data: ${response.data}");

      if (response.statusCode == 200) {
        print("✅ Joined successfully on server");

        // Immediately save the tour data if returned
        if (response.data != null && response.data['tour'] != null) {
          try {
            final tourData = response.data['tour'];
            print("📦 Saving joined tour to local DB: ${tourData['name']}");

            // Save the tour
            await db.createTour(Tour(
              id: tourData['id'] ?? '',
              name: tourData['name'] ?? 'Unknown Tour',
              startDate: tourData['start_date'] != null &&
                      tourData['start_date'].toString().isNotEmpty
                  ? DateTime.parse(tourData['start_date'])
                  : null,
              endDate: tourData['end_date'] != null &&
                      tourData['end_date'].toString().isNotEmpty
                  ? DateTime.parse(tourData['end_date'])
                  : null,
              inviteCode: tourData['invite_code'] ?? inviteCode,
              createdBy: tourData['created_by'] ?? userId,
              purpose: tourData['purpose'] ?? 'tour',
              isSynced: true,
              isDeleted: false,
              updatedAt: DateTime.now(),
            ));
            print("✅ Tour saved to local DB");

            // Save all members
            final usersList = tourData['Users'] ??
                tourData['users'] ??
                tourData['Members'] ??
                tourData['members'];
            if (usersList != null && usersList is List) {
              for (final member in usersList) {
                try {
                  final mId = (member['id'] ?? '').toString();
                  if (mId.isEmpty) continue;

                  String memberName = (member['name'] ?? 'Unknown').toString();
                  final memberEmail = member['email']?.toString();

                  // Fallback to email username if name is unknown
                  if ((memberName.toLowerCase() == 'unknown' ||
                          memberName.isEmpty) &&
                      memberEmail != null &&
                      memberEmail.contains('@')) {
                    final parts = memberEmail.split('@');
                    if (parts.isNotEmpty && parts[0].isNotEmpty) {
                      memberName =
                          parts[0][0].toUpperCase() + parts[0].substring(1);
                    }
                  }

                  await db.createUser(User(
                    id: mId,
                    name: memberName,
                    phone: member['phone']?.toString(),
                    email: memberEmail,
                    avatarUrl: (member['avatar_url'] ?? member['avatarUrl'])
                        ?.toString(),
                    purpose: (member['purpose'] ?? 'tour').toString(),
                    isMe: mId.toLowerCase() == userId.toLowerCase(),
                    isSynced: true,
                    isDeleted: false,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ));

                  final memberMeta = _memberMeta(member);
                  final mStatus = _normalizeStatus(
                      memberMeta?['status'], memberMeta?['removed_at']);
                  final mRole = _normalizeRole(memberMeta?['role']);
                  final mLeftAt = (memberMeta?['removed_at'] != null)
                      ? DateTime.tryParse(
                          memberMeta?['removed_at'].toString() ?? '')
                      : null;

                  await db.into(db.tourMembers).insert(
                      TourMember(
                        tourId: tourData['id'].toString(),
                        userId: mId,
                        status: mStatus,
                        role: mRole,
                        leftAt: mLeftAt,
                        mealCount:
                            (member['meal_count'] as num?)?.toDouble() ?? 0.0,
                        isSynced: true,
                        isDeleted: false,
                      ),
                      mode: InsertMode.insertOrReplace);
                } catch (e) {
                  print("Error saving member: $e");
                }
              }
            }

            // Save all expenses
            final expensesList = tourData['Expenses'] ?? tourData['expenses'];
            if (expensesList != null && expensesList is List) {
              for (final ex in expensesList) {
                try {
                  final exId = (ex['id'] ?? '').toString();
                  if (exId.isEmpty) continue;

                  await db.into(db.expenses).insert(
                      Expense(
                        id: exId,
                        tourId: tourData['id'].toString(),
                        payerId: (ex['payer_id'] ?? ex['payerId'])?.toString(),
                        amount:
                            double.tryParse(ex['amount']?.toString() ?? '0') ??
                                0.0,
                        title: (ex['title'] ?? 'Expense').toString(),
                        category: (ex['category'] ?? 'Others').toString(),
                        messCostType: ex['mess_cost_type']?.toString(),
                        isSynced: true,
                        isDeleted:
                            ex['isDeleted'] == true || ex['is_deleted'] == 1,
                        createdAt: ex['date'] != null
                            ? DateTime.parse(ex['date'].toString())
                            : (ex['createdAt'] != null
                                ? DateTime.parse(ex['createdAt'].toString())
                                : DateTime.now()),
                      ),
                      mode: InsertMode.insertOrReplace);

                  final splitsList = ex['ExpenseSplits'] ??
                      ex['expenseSplits'] ??
                      ex['splits'] ??
                      ex['Splits'];
                  if (splitsList != null && splitsList is List) {
                    for (final sp in splitsList) {
                      final sUserId =
                          (sp['user_id'] ?? sp['userId'] ?? '').toString();
                      if (sUserId.isEmpty) continue;

                      await db.into(db.expenseSplits).insert(
                          ExpenseSplit(
                            id: (sp['id'] ?? const Uuid().v4()).toString(),
                            expenseId: exId,
                            userId: sUserId,
                            amount: double.tryParse(
                                    sp['amount']?.toString() ?? '0') ??
                                0.0,
                            isSynced: true,
                            isDeleted: sp['isDeleted'] == true ||
                                sp['is_deleted'] == 1,
                          ),
                          mode: InsertMode.insertOrReplace);
                    }
                  }

                  final payersList = ex['ExpensePayers'] ??
                      ex['expensePayers'] ??
                      ex['payers'] ??
                      ex['Payers'];
                  if (payersList != null && payersList is List) {
                    for (final pay in payersList) {
                      final pUserId =
                          (pay['user_id'] ?? pay['userId'] ?? '').toString();
                      if (pUserId.isEmpty) continue;

                      await db.into(db.expensePayers).insert(
                          ExpensePayer(
                            id: (pay['id'] ?? const Uuid().v4()).toString(),
                            expenseId: exId,
                            userId: pUserId,
                            amount: double.tryParse(
                                    pay['amount']?.toString() ?? '0') ??
                                0.0,
                            isSynced: true,
                            isDeleted: pay['isDeleted'] == true ||
                                pay['is_deleted'] == 1,
                          ),
                          mode: InsertMode.insertOrReplace);
                    }
                  }
                } catch (e) {
                  print("Error saving expense: $e");
                }
              }
            }

            // Save all settlements
            final settlementsList =
                tourData['Settlements'] ?? tourData['settlements'];
            if (settlementsList != null && settlementsList is List) {
              for (final stItem in settlementsList) {
                try {
                  final fId =
                      (stItem['from_id'] ?? stItem['fromId'] ?? '').toString();
                  final tId =
                      (stItem['to_id'] ?? stItem['toId'] ?? '').toString();
                  if (fId.isEmpty || tId.isEmpty) continue;

                  await db.into(db.settlements).insert(
                      Settlement(
                        id: (stItem['id'] ?? const Uuid().v4()).toString(),
                        tourId: tourData['id'].toString(),
                        fromId: fId,
                        toId: tId,
                        amount: double.tryParse(
                                stItem['amount']?.toString() ?? '0') ??
                            0.0,
                        date: stItem['date'] != null
                            ? DateTime.parse(stItem['date'].toString())
                            : DateTime.now(),
                        isSynced: true,
                        isDeleted: stItem['isDeleted'] == true ||
                            stItem['is_deleted'] == 1,
                      ),
                      mode: InsertMode.insertOrReplace);
                } catch (e) {
                  print("Error saving settlement: $e");
                }
              }
            }

            // Save Program Incomes
            final incomesList = tourData['ProgramIncomes'] ??
                tourData['programIncomes'] ??
                tourData['incomes'];
            if (incomesList != null && incomesList is List) {
              for (final inc in incomesList) {
                try {
                  await db.into(db.programIncomes).insert(
                      ProgramIncome(
                        id: (inc['id'] ?? '').toString(),
                        tourId: tourData['id'].toString(),
                        amount:
                            double.tryParse(inc['amount']?.toString() ?? '0') ??
                                0.0,
                        source: (inc['source'] ?? '').toString(),
                        description: (inc['description'] ?? '').toString(),
                        collectedBy:
                            (inc['collected_by'] ?? inc['collectedBy'] ?? '')
                                .toString(),
                        date: inc['date'] != null
                            ? DateTime.parse(inc['date'].toString())
                            : DateTime.now(),
                        isSynced: true,
                        isDeleted:
                            inc['isDeleted'] == true || inc['is_deleted'] == 1,
                      ),
                      mode: InsertMode.insertOrReplace);
                } catch (e) {
                  print("Error saving income: $e");
                }
              }
            }

            print(
                "✅ Tour, members, and expenses saved successfully to local DB");
          } catch (saveError) {
            print("❌ Error saving tour locally: $saveError");
            print("Stack trace: ${saveError.toString()}");
            // Continue with sync anyway
          }
        } else {
          print("⚠️ No tour data in response, will rely on sync");
        }

        // Trigger full sync to get any additional data
        try {
          print("🔄 Starting post-join sync...");
          await startSync(userId);
          print("✅ Post-join sync completed successfully");
        } catch (syncError) {
          print("⚠️ Post-join sync failed: $syncError");
          // Don't throw here since we already saved the tour locally
          // The user can manually sync later if needed
        }

        print("=== JOIN REQUEST COMPLETE ===");
      } else {
        throw Exception(
            "Server returned ${response.statusCode}: ${response.data}");
      }
    } on DioException catch (e) {
      print("❌ DioException during join:");
      print("  Type: ${e.type}");
      print("  Message: ${e.message}");
      print("  Status Code: ${e.response?.statusCode}");
      print("  Response Data: ${e.response?.data}");

      String errorMsg = "Connection failed. ";
      if (e.type == DioExceptionType.connectionError) {
        errorMsg +=
            "Server unreachable on $baseUrl. Check your network or Vercel status.";
      } else if (e.response?.data != null &&
          e.response?.data['error'] != null) {
        errorMsg = e.response?.data['error'];
      } else {
        errorMsg += e.message ?? "Unknown error";
      }
      throw Exception(errorMsg);
    } catch (e, stackTrace) {
      print("❌ Generic error during join: $e");
      print("Stack trace: $stackTrace");
      throw Exception("Unexpected error: $e");
    }
  }

  Future<List<dynamic>> searchUsers(String query) async {
    try {
      final response = await dio
          .get('$baseUrl/users/search', queryParameters: {'query': query});
      if (response.statusCode == 200 && response.data is List) {
        return List<dynamic>.from(response.data);
      }
      return [];
    } catch (e) {
      print("Search failed: $e");
      return [];
    }
  }

  Future<void> addMemberToTour(String tourId, String userId) async {
    try {
      final response = await dio
          .post('$baseUrl/tours/$tourId/add-member', data: {'userId': userId});
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to add member');
      }
    } catch (e) {
      print("Add member failed: $e");
      throw Exception(e.toString());
    }
  }

  Future<void> updateMemberRole(
      String tourId, String userId, String role) async {
    try {
      final response = await dio.patch(
          '$baseUrl/tours/$tourId/members/$userId/role',
          data: {'role': role});
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to update role');
      }
    } catch (e) {
      print("Update role failed: $e");
      throw Exception(e.toString());
    }
  }

  /// Retroactively includes a member in ALL existing expenses of a tour.
  /// The server redistributes existing splits equally, then we pull the
  /// updated splits back into the local DB.
  Future<void> retroactiveSplit(
      String tourId, String userId, String currentUserId) async {
    try {
      // 1. Tell the server to redistribute
      final response = await dio.post(
        '$baseUrl/tours/$tourId/members/$userId/retroactive-split',
      );

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Retroactive split failed');
      }

      print("✅ Server retroactive split succeeded. Pulling fresh data...");

      // 2. Full sync so the local DB gets the server's redistributed splits
      await startSync(currentUserId);
    } catch (e) {
      print("Retroactive split failed: $e");
      throw Exception(e.toString());
    }
  }

  /// Applies retroactive split LOCALLY (offline-first) without server call.
  /// Call this before or after retroactiveSplit() depending on connectivity.
  Future<void> applyRetroactiveSplitLocally(
      String tourId, String newUserId) async {
    // Get all expenses for this tour
    final expenses = await (db.select(db.expenses)
          ..where((e) => e.tourId.equals(tourId)))
        .get();

    for (final expense in expenses) {
      // Get existing splits
      final existingSplits = await (db.select(db.expenseSplits)
            ..where((s) => s.expenseId.equals(expense.id)))
          .get();

      final alreadyIncluded = existingSplits
          .any((s) => s.userId.toLowerCase() == newUserId.toLowerCase());
      if (alreadyIncluded) continue;

      final newCount = existingSplits.length + 1;
      final newAmount = expense.amount / newCount;

      // Update existing splits
      for (final split in existingSplits) {
        await (db.update(db.expenseSplits)..where((s) => s.id.equals(split.id)))
            .write(ExpenseSplitsCompanion(
          amount: Value(newAmount),
          isSynced: const Value(false),
        ));
      }

      // Insert new split for the new member
      await db.into(db.expenseSplits).insert(
            ExpenseSplitsCompanion.insert(
              id: const Uuid().v4(),
              expenseId: expense.id,
              userId: newUserId,
              amount: newAmount,
              isSynced: const Value(false),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
    print(
        "✅ Local retroactive split applied for user $newUserId in tour $tourId");
  }

  // Join Requests
  Future<Map<String, dynamic>?> findTourByCode(String code) async {
    try {
      final response = await dio.get('$baseUrl/tours/find/$code');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } on DioException catch (e) {
      print("Find tour failed: ${e.message}");
      if (e.response?.statusCode == 401) {
        throw Exception("Authentication required. Please log in again.");
      } else if (e.response?.statusCode == 404) {
        return null; // This is a legitimate "Not Found"
      } else if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw Exception(
            "Server unreachable. Check your internet or if the backend is running at $baseUrl");
      }
      throw Exception("Find failed: ${e.message}");
    } catch (e) {
      print("Unexpected error in findTourByCode: $e");
      return null;
    }
  }

  Future<void> requestToJoin(String tourId) async {
    try {
      final response = await dio.post('$baseUrl/tours/$tourId/request-join');
      if (response.statusCode != 201) {
        throw Exception(
            response.data['error'] ?? 'Failed to send join request');
      }

      // Save locally as pending
      final jrData = response.data;
      await db.into(db.joinRequests).insert(
          JoinRequestsCompanion.insert(
            id: jrData['id'],
            tourId: tourId,
            userId: jrData['user_id'],
            userName: jrData['user_name'],
            status: const Value('pending'),
            isSynced: const Value(true),
          ),
          mode: InsertMode.insertOrReplace);
    } catch (e) {
      print("Join request failed: $e");
      throw Exception(e.toString());
    }
  }

  Future<String> regenerateInviteCode(String tourId) async {
    try {
      final response =
          await dio.post('$baseUrl/tours/$tourId/invite-code/regenerate');
      if (response.statusCode == 200 && response.data != null) {
        final inviteCode = response.data['inviteCode']?.toString();
        if (inviteCode == null || inviteCode.isEmpty) {
          throw Exception('Invalid invite code response from server');
        }
        return inviteCode;
      }
      throw Exception(
          response.data?['error'] ?? 'Failed to generate invite code');
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('Only admin can generate invite code');
      }
      if (e.response?.statusCode == 404) {
        throw Exception('Tour not found on server');
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw Exception('Server unreachable. Check internet connection.');
      }
      throw Exception(e.response?.data?['error']?.toString() ??
          e.message ??
          'Failed to generate invite code');
    }
  }

  Future<List<dynamic>> getJoinRequests(String tourId) async {
    try {
      final response = await dio.get('$baseUrl/tours/$tourId/requests');
      if (response.statusCode == 200) {
        return List<dynamic>.from(response.data);
      }
      return [];
    } catch (e) {
      print("Get requests failed: $e");
      return [];
    }
  }

  Future<void> handleJoinRequest(String requestId, String status,
      {String? role}) async {
    try {
      final response = await dio.patch('$baseUrl/tours/requests/$requestId',
          data: {'status': status, 'role': role ?? 'viewer'});
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to handle request');
      }
    } catch (e) {
      print("Handle request failed: $e");
      throw Exception(e.toString());
    }
  }
}
