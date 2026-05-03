import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import 'package:uuid/uuid.dart';

class SyncService {
  final AppDatabase db;
  final Dio dio;
  final String baseUrl;
  bool _isSyncInProgress = false;

  SyncService(this.db, this.dio, this.baseUrl) {
    debugPrint("📡 SyncService initialized with BaseURL: $baseUrl");
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

  Future<Set<String>> _getLocalOnlyTourIds() async {
    try {
      return await db.getLocalOnlyTourIds();
    } catch (e) {
      debugPrint('⚠️ Failed to load local-only tour preferences: $e');
      return <String>{};
    }
  }

  bool _hasId(String? value) => value != null && value.trim().isNotEmpty;

  Future<void> startSync(String userId) async {
    if (_isSyncInProgress) {
      debugPrint('⏭️ Sync skipped: previous sync still in progress');
      return;
    }

    _isSyncInProgress = true;
    try {
      debugPrint("Sync started for user: $userId");

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

      final allUnsyncedUsers = results[0] as List<User>;
      final allUnsyncedTours = results[1] as List<Tour>;
      final allUnsyncedExpenses = results[2] as List<Expense>;
      final allUnsyncedSplits = results[3] as List<ExpenseSplit>;
      final allUnsyncedPayers = results[4] as List<ExpensePayer>;
      final allUnsyncedMembers = results[5] as List<TourMember>;
      final allUnsyncedSettlements = results[6] as List<Settlement>;
      final allUnsyncedIncomes = results[7] as List<ProgramIncome>;
      final allUnsyncedJoinRequests = results[8] as List<JoinRequest>;

      final localOnlyTourIds = await _getLocalOnlyTourIds();

      final unsyncedTours = allUnsyncedTours
          .where((t) =>
              _hasId(t.id) &&
              _hasId(t.createdBy) &&
              !localOnlyTourIds.contains(t.id))
          .toList();

      final unsyncedExpenses = allUnsyncedExpenses
          .where((e) =>
              _hasId(e.id) &&
              _hasId(e.tourId) &&
              !localOnlyTourIds.contains(e.tourId))
          .toList();
      final syncExpenseIds = unsyncedExpenses.map((e) => e.id).toSet();

      final unsyncedSplits = allUnsyncedSplits
          .where((s) =>
              _hasId(s.id) &&
              _hasId(s.expenseId) &&
              _hasId(s.userId) &&
              syncExpenseIds.contains(s.expenseId))
          .toList();
      final unsyncedPayers = allUnsyncedPayers
          .where((p) =>
              _hasId(p.id) &&
              _hasId(p.expenseId) &&
              _hasId(p.userId) &&
              syncExpenseIds.contains(p.expenseId))
          .toList();
      final unsyncedMembers = allUnsyncedMembers
          .where((m) =>
              _hasId(m.tourId) &&
              _hasId(m.userId) &&
              !localOnlyTourIds.contains(m.tourId))
          .toList();
      final unsyncedSettlements = allUnsyncedSettlements
          .where((s) =>
              _hasId(s.id) &&
              _hasId(s.tourId) &&
              _hasId(s.fromId) &&
              _hasId(s.toId) &&
              !localOnlyTourIds.contains(s.tourId))
          .toList();
      final unsyncedIncomes = allUnsyncedIncomes
          .where((i) =>
              _hasId(i.id) &&
              _hasId(i.tourId) &&
              _hasId(i.collectedBy) &&
              !localOnlyTourIds.contains(i.tourId))
          .toList();
      final unsyncedJoinRequests = allUnsyncedJoinRequests
          .where((jr) =>
              _hasId(jr.id) &&
              _hasId(jr.tourId) &&
              _hasId(jr.userId) &&
              !localOnlyTourIds.contains(jr.tourId))
          .toList();

      final referencedUserIds = <String>{userId};
      referencedUserIds.addAll(
          unsyncedTours.map((t) => t.createdBy).where((id) => id.isNotEmpty));
      referencedUserIds
          .addAll(unsyncedExpenses.map((e) => e.payerId).whereType<String>());
      referencedUserIds.addAll(unsyncedMembers.map((m) => m.userId));
      referencedUserIds.addAll(unsyncedSplits.map((s) => s.userId));
      referencedUserIds.addAll(unsyncedPayers.map((p) => p.userId));
      referencedUserIds.addAll(unsyncedSettlements.map((s) => s.fromId));
      referencedUserIds.addAll(unsyncedSettlements.map((s) => s.toId));
      referencedUserIds.addAll(unsyncedIncomes.map((i) => i.collectedBy));
      referencedUserIds.addAll(unsyncedJoinRequests.map((jr) => jr.userId));

      final unsyncedUsers = allUnsyncedUsers
          .where((u) =>
              _hasId(u.id) && (referencedUserIds.contains(u.id) || u.isMe))
          .toList();

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
                    'avatar_url': u.avatarUrl,
                    'purpose': u.purpose
                  })
              .toList(),
          'tours': unsyncedTours
              .map((t) => {
                    'id': t.id.toLowerCase(),
                    'name': t.name,
                    'created_by': t.createdBy.toLowerCase(),
                    'invite_code': t.inviteCode,
                    'start_date': t.startDate?.toIso8601String(),
                    'end_date': t.endDate?.toIso8601String(),
                    'purpose': t.purpose,
                    'is_manager_led': t.isManagerLed,
                    'manager_id': t.managerId,
                    'is_deleted': t.isDeleted,
                  })
              .toList(),
          'expenses': unsyncedExpenses
              .map((e) => {
                    'id': e.id.toLowerCase(),
                    'tour_id': e.tourId.toLowerCase(),
                    'payer_id':
                        _hasId(e.payerId) ? e.payerId!.toLowerCase() : null,
                    'amount': e.amount,
                    'title': e.title,
                    'category': e.category,
                    'mess_cost_type': e.messCostType,
                    'date': e.createdAt.toIso8601String(),
                    'isDeleted': e.isDeleted,
                  })
              .toList(),
          'splits': unsyncedSplits
              .map((s) => {
                    'id': s.id.toLowerCase(),
                    'expense_id': s.expenseId.toLowerCase(),
                    'user_id': s.userId.toLowerCase(),
                    'amount': s.amount,
                    'isDeleted': s.isDeleted,
                  })
              .toList(),
          'payers': unsyncedPayers
              .map((p) => {
                    'id': p.id.toLowerCase(),
                    'expense_id': p.expenseId.toLowerCase(),
                    'user_id': p.userId.toLowerCase(),
                    'amount': p.amount,
                    'isDeleted': p.isDeleted,
                  })
              .toList(),
          'members': unsyncedMembers
              .map((m) => {
                    'tour_id': m.tourId,
                    'user_id': m.userId,
                    'left_at': m.leftAt?.toIso8601String(),
                    'meal_count': m.mealCount,
                    'role': m.role,
                    'status': m.status,
                    'isDeleted': m.isDeleted,
                  })
              .toList(),
          'settlements': unsyncedSettlements
              .map((s) => {
                    'id': s.id,
                    'tour_id': s.tourId,
                    'from_id': s.fromId,
                    'to_id': s.toId,
                    'amount': s.amount,
                    'date': s.date.toIso8601String(),
                    'isDeleted': s.isDeleted,
                  })
              .toList(),
          'incomes': unsyncedIncomes
              .map((i) => {
                    'id': i.id,
                    'tour_id': i.tourId,
                    'amount': i.amount,
                    'source': i.source,
                    'description': i.description,
                    'collected_by': i.collectedBy,
                    'date': i.date.toIso8601String(),
                    'isDeleted': i.isDeleted,
                  })
              .toList(),
          'joinRequests': unsyncedJoinRequests
              .map((jr) => {
                    'id': jr.id,
                    'tour_id': jr.tourId,
                    'user_id': jr.userId,
                    'user_name': jr.userName,
                    'status': jr.status,
                  })
              .toList(),
        }
      });

      if (response.statusCode == 200) {
        final pushSuccess = response.data['pushSuccess'] ?? true;
        if (pushSuccess == false) {
          final pushError = response.data['pushError'] ?? 'Unknown push error';
          debugPrint("⚠️ Push failed on server: $pushError");
          throw Exception(
              "Sync partial failure: $pushError. Server prevented local changes from being saved.");
        }

        debugPrint("✅ Server returned 200. Marking pushed items as synced.");
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

        debugPrint("🔄 Running batch update for server data...");
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
                      id: (jr['id'] ?? '').toString().toLowerCase(),
                      tourId: (st['id'] ?? '').toString().toLowerCase(),
                      userId: (jr['user_id'] ?? '').toString().toLowerCase(),
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
                  id: (st['id'] ?? '').toString().toLowerCase(),
                  name: st['name'] ?? 'Unknown Tour',
                  startDate: Value((st['startDate'] ?? st['start_date']) != null
                      ? DateTime.tryParse((st['startDate'] ?? st['start_date']).toString())
                      : null),
                  endDate: Value((st['endDate'] ?? st['end_date']) != null
                      ? DateTime.tryParse((st['endDate'] ?? st['end_date']).toString())
                      : null),
                  inviteCode: inviteCodeField,
                  createdBy: st['created_by'] ?? '',
                  purpose: Value(st['purpose'] ?? 'tour'),
                  isManagerLed: Value(_parseBool(st['is_manager_led'] ?? st['isManagerLed'])),
                  managerId: Value(st['manager_id']?.toString() ?? st['managerId']?.toString()),
                  isDeleted: Value(_parseBool(st['is_deleted'] ?? st['isDeleted'])),
                  updatedAt: Value((st['updatedAt'] ?? st['updated_at']) != null
                       ? DateTime.tryParse((st['updatedAt'] ?? st['updated_at']).toString())
                       : null),
                  isSynced: const Value(true),
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
                      id: (su['id'] ?? '').toString().toLowerCase(),
                      name: userName,
                      phone: Value(su['phone']),
                      email: Value(userEmail),
                      avatarUrl: Value(su['avatar_url']),
                      purpose: Value(su['purpose']),
                      isMe: Value(su['id'].toString().toLowerCase() ==
                          userId.toLowerCase()),
                      isDeleted: Value(_parseBool(su['isDeleted'] ?? su['is_deleted'])),
                      isSynced: const Value(true),
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
                      tourId: st['id'].toString().toLowerCase(),
                      userId: su['id'].toString().toLowerCase(),
                      status: Value(suStatus),
                      leftAt: Value(suLeftAt),
                      role: Value(suRole),
                      mealCount: Value(double.tryParse(
                              su['meal_count']?.toString() ?? '0') ??
                          0.0),
                      isDeleted: Value(_parseBool(su['isDeleted'] ?? su['is_deleted'])),
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
                      id: se['id'].toString().toLowerCase(),
                      tourId: st['id'].toString().toLowerCase(),
                      payerId: Value(se['payer_id']?.toString().toLowerCase()),
                      amount:
                          double.tryParse(se['amount']?.toString() ?? '0') ??
                              0.0,
                      title: se['title'] ?? 'Unknown',
                      category: (se['category'] ?? 'Others').toString(),
                      messCostType: Value(se['mess_cost_type']?.toString()),
                      isSynced: const Value(true),
                      isDeleted: Value(_parseBool(se['isDeleted'] ?? se['is_deleted'])),
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
                          id: (ss['id'] ?? "${se['id']}_${ss['user_id']}")
                              .toString()
                              .toLowerCase(),
                          expenseId: se['id'].toString().toLowerCase(),
                          userId: ss['user_id'].toString().toLowerCase(),
                          amount: double.tryParse(
                                  ss['amount']?.toString() ?? '0') ??
                              0.0,
                          isSynced: const Value(true),
                          isDeleted: Value(ss['isDeleted'] == true ||
                              ss['is_deleted'] == true ||
                              ss['is_deleted'] == 1),
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
                          id: (sp['id'] ?? "${se['id']}_${sp['user_id']}")
                              .toString()
                              .toLowerCase(),
                          expenseId: se['id'].toString().toLowerCase(),
                          userId: sp['user_id'].toString().toLowerCase(),
                          amount: double.tryParse(
                                  sp['amount']?.toString() ?? '0') ??
                              0.0,
                          isSynced: const Value(true),
                          isDeleted: Value(_parseBool(sp['isDeleted'] ?? sp['is_deleted'])),
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
                      id: (ss['id'] ??
                              "${st['id']}_${fromId}_${toId}_${ss['amount']}")
                          .toString()
                          .toLowerCase(),
                      tourId: (st['id'] ?? '').toString().toLowerCase(),
                      fromId: fromId.toLowerCase(),
                      toId: toId.toLowerCase(),
                      amount:
                          double.tryParse(ss['amount']?.toString() ?? '0') ??
                              0.0,
                      date: Value(ss['date'] != null
                          ? DateTime.parse(ss['date'].toString())
                          : DateTime.now()),
                      isSynced: const Value(true),
                      isDeleted: Value(_parseBool(ss['isDeleted'] ?? ss['is_deleted'])),
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
                      id: (inc['id'] ??
                              "${st['id']}_${inc['source']}_${inc['amount']}")
                          .toString()
                          .toLowerCase(),
                      tourId: (st['id'] ?? '').toString().toLowerCase(),
                      amount:
                          double.tryParse(inc['amount']?.toString() ?? '0') ??
                              0.0,
                      source: (inc['source'] ?? '').toString(),
                      description: Value((inc['description'] ?? '').toString()),
                      collectedBy:
                          (inc['collected_by'] ?? inc['collectedBy'] ?? '')
                              .toString()
                              .toLowerCase(),
                      date: Value(inc['date'] != null
                          ? DateTime.parse(inc['date'].toString())
                          : DateTime.now()),
                      isSynced: const Value(true),
                      isDeleted: Value(_parseBool(inc['isDeleted'] ?? inc['is_deleted'])),
                    ),
                    mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Join Requests
            final joinReqs = st['JoinRequests'] ?? st['joinRequests'];
            if (joinReqs != null && joinReqs is List) {
              for (final jr in joinReqs) {
                batch.insert(
                    db.joinRequests,
                    JoinRequestsCompanion.insert(
                      id: (jr['id'] ?? '').toString().toLowerCase(),
                      tourId: (st['id'] ?? '').toString().toLowerCase(),
                      userId: (jr['userId'] ?? jr['user_id'] ?? '')
                          .toString()
                          .toLowerCase(),
                      userName: (jr['userName'] ?? jr['user_name'] ?? 'Unknown')
                          .toString(),
                      status: jr['status'] ?? 'pending',
                    ),
                    mode: InsertMode.insertOrReplace);
              }
            }
          }
        });

        // Handle server-side deletions (e.g. tour deleted by another user)
        // by checking against the authoritative allTourIds list.
        final allTourIdsList = response.data['allTourIds'] as List?;
        if (allTourIdsList != null) {
          final Set<String> activeServerTourIds = 
              allTourIdsList.map((e) => e.toString().toLowerCase()).toSet();
          
          final localTours = await db.getAllTours();
          final localOnlyTourIds = await _getLocalOnlyTourIds();
          
          for (final lt in localTours) {
            final lowerId = lt.id.toLowerCase();
            // If a tour is synced (not local-only) and the server doesn't list it as active,
            // it means it was deleted or we were removed from it.
            if (!localOnlyTourIds.contains(lowerId) && !activeServerTourIds.contains(lowerId)) {
               debugPrint("🗑️ Pruning local tour not found on server: \${lt.name} ($lowerId)");
               await db.hardDeleteTourWithDetails(lt.id);
            }
          }
        }

        if (response.data['timestamp'] != null) {
          await db.setSyncMetadata(
              'last_sync_$userId', response.data['timestamp'].toString());
        }
        debugPrint("✅ Sync completed successfully.");
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String errorMsg = 'Sync failed';

      if (e.response?.data != null && e.response?.data is Map) {
        final data = e.response!.data as Map;
        final serverMessage =
            (data['message'] ?? data['error'] ?? '').toString().trim();
        final details = (data['details'] ?? '').toString().trim();

        if (serverMessage.isNotEmpty) {
          errorMsg = serverMessage;
        } else if ((data['error'] ?? '').toString().trim().isNotEmpty) {
          errorMsg = data['error'].toString().trim();
        }

        if (details.isNotEmpty) {
          errorMsg = '$errorMsg: $details';
        }
      } else if ((e.message ?? '').trim().isNotEmpty) {
        errorMsg = e.message!.trim();
      }

      final endpoint = e.requestOptions.path;
      final statusText = statusCode != null ? ' [HTTP $statusCode]' : '';
      debugPrint(
          '❌ Sync Engine DioError$statusText on $endpoint (type: ${e.type}): $errorMsg');
      throw Exception(errorMsg);
    } catch (e) {
      debugPrint("❌ Sync Engine Generic Error: $e");
      rethrow;
    } finally {
      _isSyncInProgress = false;
    }
  }

  Future<void> joinByInvite(String inviteCode, String userId, String userName,
      {String? email, String? avatarUrl, String? purpose}) async {
    try {
      debugPrint("=== JOIN REQUEST START ===");
      debugPrint("Invite Code: $inviteCode");
      debugPrint("User ID: $userId");
      debugPrint("User Name: $userName");

      final response = await dio.post('$baseUrl/tours/join', data: {
        'invite_code': inviteCode,
        'user_id': userId,
        'user_name': userName,
        'email': email,
        'avatar_url': avatarUrl,
        'purpose': purpose
      });

      debugPrint("Response Status: ${response.statusCode}");
      debugPrint("Response Data: ${response.data}");

      if (response.statusCode == 200) {
        debugPrint("✅ Joined successfully on server");

        // Immediately save the tour data if returned
        if (response.data != null && response.data['tour'] != null) {
          try {
            final tourData = response.data['tour'];
            debugPrint(
                "📦 Saving joined tour to local DB: ${tourData['name']}");

            // Save the tour
            await db.createTour(Tour(
              id: tourData['id'] ?? '',
              name: tourData['name'] ?? 'Unknown Tour',
              startDate: (tourData['startDate'] ?? tourData['start_date']) != null &&
                      (tourData['startDate'] ?? tourData['start_date']).toString().isNotEmpty
                  ? DateTime.parse((tourData['startDate'] ?? tourData['start_date']).toString())
                  : null,
              endDate: (tourData['endDate'] ?? tourData['end_date']) != null &&
                      (tourData['endDate'] ?? tourData['end_date']).toString().isNotEmpty
                  ? DateTime.parse((tourData['endDate'] ?? tourData['end_date']).toString())
                  : null,
              inviteCode: tourData['inviteCode'] ?? tourData['invite_code'] ?? inviteCode,
              createdBy: tourData['createdBy'] ?? tourData['created_by'] ?? userId,
              purpose: tourData['purpose'] ?? 'tour',
              isManagerLed: _parseBool(tourData['isManagerLed'] ?? tourData['is_manager_led']),
              managerId: tourData['managerId'] ?? tourData['manager_id'],
              isSynced: true,
              isDeleted: false,
            ));
            debugPrint("✅ Tour saved to local DB");

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
                  debugPrint("Error saving member: $e");
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
                            id: (sp['id'] ?? const Uuid().v4())
                                .toString()
                                .toLowerCase(),
                            expenseId: exId,
                            userId: sUserId.toLowerCase(),
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
                            id: (pay['id'] ?? const Uuid().v4())
                                .toString()
                                .toLowerCase(),
                            expenseId: exId,
                            userId: pUserId.toLowerCase(),
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
                  debugPrint("Error saving expense: $e");
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
                        id: (stItem['id'] ?? const Uuid().v4())
                            .toString()
                            .toLowerCase(),
                        tourId: tourData['id'].toString().toLowerCase(),
                        fromId: fId.toLowerCase(),
                        toId: tId.toLowerCase(),
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
                  debugPrint("Error saving settlement: $e");
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
                        id: (inc['id'] ?? '').toString().toLowerCase(),
                        tourId: tourData['id'].toString().toLowerCase(),
                        amount:
                            double.tryParse(inc['amount']?.toString() ?? '0') ??
                                0.0,
                        source: (inc['source'] ?? '').toString(),
                        description: (inc['description'] ?? '').toString(),
                        collectedBy:
                            (inc['collected_by'] ?? inc['collectedBy'] ?? '')
                                .toString()
                                .toLowerCase(),
                        date: inc['date'] != null
                            ? DateTime.parse(inc['date'].toString())
                            : DateTime.now(),
                        isSynced: true,
                        isDeleted:
                            inc['isDeleted'] == true || inc['is_deleted'] == 1,
                      ),
                      mode: InsertMode.insertOrReplace);
                } catch (e) {
                  debugPrint("Error saving income: $e");
                }
              }
            }

            debugPrint(
                "✅ Tour, members, and expenses saved successfully to local DB");
          } catch (saveError) {
            debugPrint("❌ Error saving tour locally: $saveError");
            debugPrint("Stack trace: ${saveError.toString()}");
            // Continue with sync anyway
          }
        } else {
          debugPrint("⚠️ No tour data in response, will rely on sync");
        }

        // Trigger full sync to get any additional data
        try {
          debugPrint("🔄 Starting post-join sync...");
          await startSync(userId);
          debugPrint("✅ Post-join sync completed successfully");
        } catch (syncError) {
          debugPrint("⚠️ Post-join sync failed: $syncError");
          // Don't throw here since we already saved the tour locally
          // The user can manually sync later if needed
        }

        debugPrint("=== JOIN REQUEST COMPLETE ===");
      } else {
        throw Exception(
            "Server returned ${response.statusCode}: ${response.data}");
      }
    } on DioException catch (e) {
      debugPrint("❌ DioException during join:");
      debugPrint("  Type: ${e.type}");
      debugPrint("  Message: ${e.message}");
      debugPrint("  Status Code: ${e.response?.statusCode}");
      debugPrint("  Response Data: ${e.response?.data}");

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
      debugPrint("❌ Generic error during join: $e");
      debugPrint("Stack trace: $stackTrace");
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
      debugPrint("Search failed: $e");
      return [];
    }
  }

  Future<void> addMemberToTour(String tourId, String userId) async {
    try {
      final response = await dio
          .post('$baseUrl/tours/$tourId/add-member', data: {'userId': userId});
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to send invitation');
      }
    } on DioException catch (e) {
      // Extract detailed error info from DioException
      final statusCode = e.response?.statusCode ?? 0;
      final errorMsg = e.response?.data?['error']?.toString() ??
          e.message ??
          'Failed to send invitation';
      debugPrint(
          "❌ Dio Error [HTTP $statusCode] POST $baseUrl/tours/$tourId/add-member (type: ${e.type}) | server: $errorMsg");
      debugPrint("Add member failed: $e");
      // Throw with status code and error message so caller can identify 403 errors
      throw Exception("HTTP $statusCode: $errorMsg");
    } catch (e) {
      debugPrint("Add member failed: $e");
      throw Exception(e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> getMyInvitations() async {
    try {
      final response = await dio.get('$baseUrl/tours/invitations/my');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint("Get my invitations failed: $e");
      return [];
    }
  }

  Future<void> respondToInvitation(String tourId, String action) async {
    try {
      final response = await dio.patch(
        '$baseUrl/tours/$tourId/invitations/respond',
        data: {'action': action},
      );
      if (response.statusCode != 200) {
        throw Exception(
            response.data['error'] ?? 'Failed to respond invitation');
      }
    } catch (e) {
      debugPrint("Respond invitation failed: $e");
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
      debugPrint("Update role failed: $e");
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

      debugPrint("✅ Server retroactive split succeeded. Pulling fresh data...");

      // 2. Full sync so the local DB gets the server's redistributed splits
      await startSync(currentUserId);
    } catch (e) {
      debugPrint("Retroactive split failed: $e");
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

      final totalAmount = expense.amount;
      final newCount = existingSplits.length + 1;

      // Calculate precise equal share (round down to 2 decimals)
      final equalAmount = (totalAmount / newCount * 100).floor() / 100.0;
      // Calculate the remainder leftover from rounding
      final remainder =
          (totalAmount - (equalAmount * newCount) * 100).round() / 100.0;

      // Update existing splits
      for (int i = 0; i < existingSplits.length; i++) {
        final split = existingSplits[i];
        // Give the remainder to the first person to keep the total exact
        final currentAmount = i == 0 ? (equalAmount + remainder) : equalAmount;

        await (db.update(db.expenseSplits)..where((s) => s.id.equals(split.id)))
            .write(ExpenseSplitsCompanion(
          amount: Value(currentAmount),
          isSynced: const Value(false),
        ));
      }

      // Insert new split for the new member
      await db.into(db.expenseSplits).insert(
            ExpenseSplitsCompanion.insert(
              id: const Uuid().v4(),
              expenseId: expense.id,
              userId: newUserId,
              amount: equalAmount,
              isSynced: const Value(false),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
    debugPrint(
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
      debugPrint("Find tour failed: ${e.message}");
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
      debugPrint("Unexpected error in findTourByCode: $e");
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
      debugPrint("Join request failed: $e");
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
      debugPrint("Get requests failed: $e");
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
      debugPrint("Handle request failed: $e");
      throw Exception(e.toString());
    }
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final s = value.toLowerCase();
      return s == 'true' || s == '1';
    }
    return false;
  }
}
