import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:io' show Platform;
import 'package:uuid/uuid.dart';

class SyncService {
  final AppDatabase db;
  final Dio dio;
  
  String get baseUrl {
    // Check developer overrides or environment
    if (kDebugMode) {
      if (kIsWeb) return 'http://127.0.0.1:3000';
      
      // For Mobile (Android Emulator uses 10.0.2.2 to access host's localhost)
      try {
        if (Platform.isAndroid) return 'http://10.0.2.2:3000';
        if (Platform.isIOS) return 'http://localhost:3000';
      } catch (e) {
        // Platform check might fail on web if not careful, but kIsWeb guards it
      }
      return 'http://localhost:3000';
    }
    
    // PRODUCTION URL - https://tour-manager-navy.vercel.app
    return 'https://tour-manager-navy.vercel.app'; 
  }

  SyncService(this.db, this.dio) {
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print("📡 API: $obj"),
    ));

    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        // startSync(userId); // Needs userId from context outside
      }
    });
    
    print("📡 SyncService initialized with BaseURL: $baseUrl");
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
          'users': unsyncedUsers.map((u) => {
            'id': u.id, 'name': u.name, 'phone': u.phone, 'email': u.email,
            'avatarUrl': u.avatarUrl, 'purpose': u.purpose
          }).toList(),
          'tours': unsyncedTours.map((t) => {
            'id': t.id, 'name': t.name, 'createdBy': t.createdBy,
            'inviteCode': t.inviteCode, 'startDate': t.startDate?.toIso8601String(),
            'endDate': t.endDate?.toIso8601String(),
          }).toList(),
          'expenses': unsyncedExpenses.map((e) => {
            'id': e.id, 'tourId': e.tourId, 'payerId': e.payerId, 'amount': e.amount,
            'title': e.title, 'category': e.category, 'messCostType': e.messCostType,
            'createdAt': e.createdAt.toIso8601String(),
          }).toList(),
          'splits': unsyncedSplits.map((s) => {
            'id': s.id, 'expenseId': s.expenseId, 'userId': s.userId, 'amount': s.amount,
          }).toList(),
          'payers': unsyncedPayers.map((p) => {
            'id': p.id, 'expenseId': p.expenseId, 'userId': p.userId, 'amount': p.amount,
          }).toList(),
          'members': unsyncedMembers.map((m) => {
            'tourId': m.tourId, 'userId': m.userId, 'leftAt': m.leftAt?.toIso8601String(), 
            'mealCount': m.mealCount, 'role': m.role,
          }).toList(),
          'settlements': unsyncedSettlements.map((s) => {
            'id': s.id, 'tourId': s.tourId, 'fromId': s.fromId, 'toId': s.toId, 'amount': s.amount, 'date': s.date.toIso8601String(),
          }).toList(),
          'incomes': unsyncedIncomes.map((i) => {
            'id': i.id, 'tourId': i.tourId, 'amount': i.amount, 'source': i.source,
            'description': i.description, 'collectedBy': i.collectedBy, 'date': i.date.toIso8601String(),
          }).toList(),
          'joinRequests': unsyncedJoinRequests.map((jr) => {
            'id': jr.id, 'tourId': jr.tourId, 'userId': jr.userId, 'userName': jr.userName, 'status': jr.status,
          }).toList(),
        }
      });

      if (response.statusCode == 200) {
        // Mark as synced locally & Pulled data within a batch for efficiency
        await db.batch((batch) {
          // 2. Mark Pushed data as synced
          for (final u in unsyncedUsers) db.markUserSynced(u.id);
          for (final t in unsyncedTours) db.markTourSynced(t.id);
          for (final m in unsyncedMembers) db.markTourMemberSynced(m.tourId, m.userId);
          for (final e in unsyncedExpenses) db.markExpenseSynced(e.id);
          for (final s in unsyncedSplits) db.markSplitSynced(s.id);
          for (final p in unsyncedPayers) db.markExpensePayerSynced(p.id);
          for (final s in unsyncedSettlements) db.markSettlementSynced(s.id);
          for (final i in unsyncedIncomes) db.markProgramIncomeSynced(i.id);
          for (final jr in unsyncedJoinRequests) db.markJoinRequestSynced(jr.id);

          final serverTours = response.data['tours'] as List;
          for (final st in serverTours) {
            // Sync Join Requests (if returned in tour data or separately)
            final jrList = st['JoinRequests'] ?? st['joinRequests'];
            if (jrList != null && jrList is List) {
              for (final jr in jrList) {
                batch.insert(db.joinRequests, JoinRequestsCompanion.insert(
                  id: jr['id'],
                  tourId: st['id'],
                  userId: jr['user_id'],
                  userName: jr['user_name'],
                  status: Value(jr['status']),
                  isSynced: const Value(true),
                ), mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Tour
            batch.insert(db.tours, ToursCompanion.insert(
              id: st['id'],
              name: st['name'],
              startDate: Value(st['start_date'] != null ? DateTime.parse(st['start_date']) : null),
              endDate: Value(st['end_date'] != null ? DateTime.parse(st['end_date']) : null),
              inviteCode: Value(st['invite_code']),
              createdBy: st['created_by'],
              purpose: Value(st['purpose'] ?? 'tour'),
              isSynced: const Value(true),
              updatedAt: Value(DateTime.now()),
            ), mode: InsertMode.insertOrReplace);

            // Sync Members
            if (st['Users'] != null) {
              for (final su in st['Users']) {
                String userName = (su['name'] ?? 'Unknown').toString();
                final userEmail = su['email']?.toString();
                
                if ((userName.toLowerCase() == 'unknown' || userName.isEmpty) && 
                    userEmail != null && userEmail.contains('@')) {
                  final parts = userEmail.split('@');
                  if (parts.isNotEmpty && parts[0].isNotEmpty) {
                    userName = parts[0][0].toUpperCase() + parts[0].substring(1);
                  }
                }

                batch.insert(db.users, UsersCompanion.insert(
                  id: su['id'],
                  name: userName,
                  phone: Value(su['phone']),
                  email: Value(userEmail),
                  avatarUrl: Value(su['avatar_url']),
                  purpose: Value(su['purpose']),
                  isMe: Value(su['id'] == userId),
                  isSynced: const Value(true),
                  updatedAt: Value(DateTime.now()),
                ), mode: InsertMode.insertOrReplace);

                // Add member connection
                String suStatus = 'active';
                if (su['TourMember'] != null && su['TourMember']['status'] != null) {
                  suStatus = su['TourMember']['status'].toString().toLowerCase().trim();
                } else if (su['TourMember'] != null && su['TourMember']['removed_at'] != null) {
                  suStatus = 'removed';
                }
                final suLeftAt = (su['TourMember'] != null && su['TourMember']['removed_at'] != null) 
                    ? DateTime.parse(su['TourMember']['removed_at'].toString()) 
                    : null;
                final suRole = (su['TourMember'] != null && su['TourMember']['role'] != null)
                    ? su['TourMember']['role'].toString()
                    : 'viewer'; // default to viewer if undefined
                
                batch.insert(db.tourMembers, TourMembersCompanion.insert(
                  tourId: st['id'],
                  userId: su['id'],
                  status: Value(suStatus),
                  leftAt: Value(suLeftAt),
                  role: Value(suRole),
                  mealCount: Value((su['meal_count'] as num?)?.toDouble() ?? 0.0),
                  isSynced: const Value(true),
                ), mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Expenses
            if (st['Expenses'] != null) {
              for (final se in st['Expenses']) {
                batch.insert(db.expenses, ExpensesCompanion.insert(
                  id: se['id'],
                  tourId: st['id'],
                  payerId: Value(se['payer_id']),
                  amount: (se['amount'] as num).toDouble(),
                  title: se['title'],
                  category: (se['category'] ?? 'Others').toString(),
                  messCostType: Value(se['mess_cost_type']),
                  isSynced: const Value(true),
                  createdAt: Value(DateTime.parse(se['date'])),
                ), mode: InsertMode.insertOrReplace);

                // Sync Splits
                if (se['ExpenseSplits'] != null) {
                  for (final ss in se['ExpenseSplits']) {
                    batch.insert(db.expenseSplits, ExpenseSplitsCompanion.insert(
                      id: ss['id'] ?? const Uuid().v4(),
                      expenseId: se['id'],
                      userId: ss['user_id'],
                      amount: (ss['amount'] as num).toDouble(),
                      isSynced: const Value(true),
                    ), mode: InsertMode.insertOrReplace);
                  }
                }

                // Sync Payers
                if (se['ExpensePayers'] != null) {
                  for (final sp in se['ExpensePayers']) {
                    batch.insert(db.expensePayers, ExpensePayersCompanion.insert(
                      id: sp['id'] ?? const Uuid().v4(),
                      expenseId: se['id'],
                      userId: sp['user_id'],
                      amount: (sp['amount'] as num).toDouble(),
                      isSynced: const Value(true),
                    ), mode: InsertMode.insertOrReplace);
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

                batch.insert(db.settlements, SettlementsCompanion.insert(
                  id: (ss['id'] ?? '').toString(),
                  tourId: (st['id'] ?? '').toString(),
                  fromId: fromId,
                  toId: toId,
                  amount: double.tryParse(ss['amount']?.toString() ?? '0') ?? 0.0,
                  date: Value(ss['date'] != null ? DateTime.parse(ss['date'].toString()) : DateTime.now()),
                  isSynced: const Value(true),
                ), mode: InsertMode.insertOrReplace);
              }
            }

            // Sync Program Incomes
            final incomes = st['ProgramIncomes'] ?? st['programIncomes'] ?? st['incomes'];
            if (incomes != null && incomes is List) {
              for (final inc in incomes) {
                batch.insert(db.programIncomes, ProgramIncomesCompanion.insert(
                  id: (inc['id'] ?? '').toString(),
                  tourId: (st['id'] ?? '').toString(),
                  amount: double.tryParse(inc['amount']?.toString() ?? '0') ?? 0.0,
                  source: (inc['source'] ?? '').toString(),
                  description: Value((inc['description'] ?? '').toString()),
                  collectedBy: (inc['collected_by'] ?? inc['collectedBy'] ?? '').toString(),
                  date: Value(inc['date'] != null ? DateTime.parse(inc['date'].toString()) : DateTime.now()),
                  isSynced: const Value(true),
                ), mode: InsertMode.insertOrReplace);
              }
            }
          }
        });

        // 4. Handle Deletions (Membership changes)
        final allTourIds = (response.data['allTourIds'] as List?)?.map((id) => id.toString()).toSet();
        if (allTourIds != null) {
          final localTours = await db.select(db.tours).get();
          for (final lt in localTours) {
            if (lt.isSynced && !allTourIds.contains(lt.id)) {
               print("🗑️ Removing tour ${lt.name} - no longer a member");
               await db.deleteTourWithDetails(lt.id); 
            }
          }
        }

        await db.setSyncMetadata('last_sync_$userId', response.data['timestamp']);
      }
      print("Sync completed.");
    } catch (e) {
      print("Sync failed: $e");
    }
  }

  Future<void> joinByInvite(String inviteCode, String userId, String userName, {String? email, String? avatarUrl, String? purpose}) async {
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
              startDate: tourData['start_date'] != null && tourData['start_date'].toString().isNotEmpty 
                ? DateTime.parse(tourData['start_date']) 
                : null,
              endDate: tourData['end_date'] != null && tourData['end_date'].toString().isNotEmpty
                ? DateTime.parse(tourData['end_date']) 
                : null,
              inviteCode: tourData['invite_code'] ?? inviteCode,
              createdBy: tourData['created_by'] ?? userId,
              purpose: tourData['purpose'] ?? 'tour',
              isSynced: true,
              updatedAt: DateTime.now(),
            ));
            print("✅ Tour saved to local DB");
            
            // Save all members
            final usersList = tourData['Users'] ?? tourData['users'] ?? tourData['Members'] ?? tourData['members'];
            if (usersList != null && usersList is List) {
              for (final member in usersList) {
                try {
                  final mId = (member['id'] ?? '').toString();
                  if (mId.isEmpty) continue;
                  
                  String memberName = (member['name'] ?? 'Unknown').toString();
                  final memberEmail = member['email']?.toString();
                  
                  // Fallback to email username if name is unknown
                  if ((memberName.toLowerCase() == 'unknown' || memberName.isEmpty) && 
                      memberEmail != null && memberEmail.contains('@')) {
                    final parts = memberEmail.split('@');
                    if (parts.isNotEmpty && parts[0].isNotEmpty) {
                      memberName = parts[0][0].toUpperCase() + parts[0].substring(1);
                    }
                  }

                  await db.createUser(User(
                    id: mId,
                    name: memberName,
                    phone: member['phone']?.toString(),
                    email: memberEmail,
                    avatarUrl: (member['avatar_url'] ?? member['avatarUrl'])?.toString(),
                    purpose: (member['purpose'] ?? 'tour').toString(),
                    isMe: mId == userId,
                    isSynced: true,
                    updatedAt: DateTime.now(),
                  ));
                  
                  final mStatus = (member['TourMember'] != null) ? (member['TourMember']['status'] ?? 'active') : 'active';
                  final mRole = (member['TourMember'] != null) ? (member['TourMember']['role'] ?? 'editor') : 'editor';
                  final mLeftAt = (member['TourMember'] != null && member['TourMember']['removed_at'] != null)
                      ? DateTime.parse(member['TourMember']['removed_at'].toString())
                      : null;

                  await db.into(db.tourMembers).insert(TourMember(
                    tourId: tourData['id'].toString(),
                    userId: mId,
                    status: mStatus,
                    role: mRole,
                    leftAt: mLeftAt,
                    mealCount: (member['meal_count'] as num?)?.toDouble() ?? 0.0,
                    isSynced: true,
                  ), mode: InsertMode.insertOrReplace);
                } catch (e) { print("Error saving member: $e"); }
              }
            }

            // Save all expenses
            final expensesList = tourData['Expenses'] ?? tourData['expenses'];
            if (expensesList != null && expensesList is List) {
              for (final ex in expensesList) {
                try {
                  final exId = (ex['id'] ?? '').toString();
                  if (exId.isEmpty) continue;
                  
                  await db.into(db.expenses).insert(Expense(
                    id: exId,
                    tourId: tourData['id'].toString(),
                    payerId: (ex['payer_id'] ?? ex['payerId'])?.toString(),
                    amount: double.tryParse(ex['amount']?.toString() ?? '0') ?? 0.0,
                    title: (ex['title'] ?? 'Expense').toString(),
                    category: (ex['category'] ?? 'Others').toString(),
                    messCostType: ex['mess_cost_type']?.toString(),
                    isSynced: true,
                    createdAt: ex['date'] != null ? DateTime.parse(ex['date'].toString()) : (ex['createdAt'] != null ? DateTime.parse(ex['createdAt'].toString()) : DateTime.now()),
                  ), mode: InsertMode.insertOrReplace);

                  final splitsList = ex['ExpenseSplits'] ?? ex['expenseSplits'] ?? ex['splits'] ?? ex['Splits'];
                  if (splitsList != null && splitsList is List) {
                    for (final sp in splitsList) {
                      final sUserId = (sp['user_id'] ?? sp['userId'] ?? '').toString();
                      if (sUserId.isEmpty) continue;
                      
                      await db.into(db.expenseSplits).insert(ExpenseSplit(
                        id: (sp['id'] ?? const Uuid().v4()).toString(),
                        expenseId: exId,
                        userId: sUserId,
                        amount: double.tryParse(sp['amount']?.toString() ?? '0') ?? 0.0,
                        isSynced: true,
                      ), mode: InsertMode.insertOrReplace);
                    }
                  }

                  final payersList = ex['ExpensePayers'] ?? ex['expensePayers'] ?? ex['payers'] ?? ex['Payers'];
                  if (payersList != null && payersList is List) {
                    for (final pay in payersList) {
                      final pUserId = (pay['user_id'] ?? pay['userId'] ?? '').toString();
                      if (pUserId.isEmpty) continue;

                      await db.into(db.expensePayers).insert(ExpensePayer(
                        id: (pay['id'] ?? const Uuid().v4()).toString(),
                        expenseId: exId,
                        userId: pUserId,
                        amount: double.tryParse(pay['amount']?.toString() ?? '0') ?? 0.0,
                        isSynced: true,
                      ), mode: InsertMode.insertOrReplace);
                    }
                  }
                } catch (e) { print("Error saving expense: $e"); }
              }
            }

            // Save all settlements
            final settlementsList = tourData['Settlements'] ?? tourData['settlements'];
            if (settlementsList != null && settlementsList is List) {
              for (final stItem in settlementsList) {
                try {
                  final fId = (stItem['from_id'] ?? stItem['fromId'] ?? '').toString();
                  final tId = (stItem['to_id'] ?? stItem['toId'] ?? '').toString();
                  if (fId.isEmpty || tId.isEmpty) continue;

                  await db.into(db.settlements).insert(Settlement(
                    id: (stItem['id'] ?? const Uuid().v4()).toString(),
                    tourId: tourData['id'].toString(),
                    fromId: fId,
                    toId: tId,
                    amount: double.tryParse(stItem['amount']?.toString() ?? '0') ?? 0.0,
                    date: stItem['date'] != null ? DateTime.parse(stItem['date'].toString()) : DateTime.now(),
                    isSynced: true,
                  ), mode: InsertMode.insertOrReplace);
                } catch (e) { print("Error saving settlement: $e"); }
              }
            }

            // Save Program Incomes
            final incomesList = tourData['ProgramIncomes'] ?? tourData['programIncomes'] ?? tourData['incomes'];
            if (incomesList != null && incomesList is List) {
              for (final inc in incomesList) {
                try {
                  await db.into(db.programIncomes).insert(ProgramIncome(
                    id: (inc['id'] ?? '').toString(),
                    tourId: tourData['id'].toString(),
                    amount: double.tryParse(inc['amount']?.toString() ?? '0') ?? 0.0,
                    source: (inc['source'] ?? '').toString(),
                    description: (inc['description'] ?? '').toString(),
                    collectedBy: (inc['collected_by'] ?? inc['collectedBy'] ?? '').toString(),
                    date: inc['date'] != null ? DateTime.parse(inc['date'].toString()) : DateTime.now(),
                    isSynced: true,
                  ), mode: InsertMode.insertOrReplace);
                } catch (e) { print("Error saving income: $e"); }
              }
            }
            
            print("✅ Tour, members, and expenses saved successfully to local DB");
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
        throw Exception("Server returned ${response.statusCode}: ${response.data}");
      }
    } on DioException catch (e) {
      print("❌ DioException during join:");
      print("  Type: ${e.type}");
      print("  Message: ${e.message}");
      print("  Status Code: ${e.response?.statusCode}");
      print("  Response Data: ${e.response?.data}");
      
      String errorMsg = "Connection failed. ";
      if (e.type == DioExceptionType.connectionError) {
        errorMsg += "Server unreachable on $baseUrl. ";
        if (kDebugMode) {
          errorMsg += "\nHints: \n1. Check if backend is running (npm run dev) \n2. Check port 3000 \n3. Is CORS allowed?";
        }
      } else if (e.response?.data != null && e.response?.data['error'] != null) {
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
      final response = await dio.get('$baseUrl/users/search', queryParameters: {'query': query});
      if (response.statusCode == 200) {
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
      final response = await dio.post('$baseUrl/tours/$tourId/add-member', data: {'userId': userId});
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to add member');
      }
    } catch (e) {
      print("Add member failed: $e");
      throw Exception(e.toString());
    }
  }

  Future<void> updateMemberRole(String tourId, String userId, String role) async {
    try {
      final response = await dio.patch('$baseUrl/tours/$tourId/members/$userId/role', data: {'role': role});
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to update role');
      }
    } catch (e) {
      print("Update role failed: $e");
      throw Exception(e.toString());
    }
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
      } else if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw Exception("Server unreachable. Check your internet or if the backend is running at $baseUrl");
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
        throw Exception(response.data['error'] ?? 'Failed to send join request');
      }
      
      // Save locally as pending
      final jrData = response.data;
      await db.into(db.joinRequests).insert(JoinRequestsCompanion.insert(
        id: jrData['id'],
        tourId: tourId,
        userId: jrData['user_id'],
        userName: jrData['user_name'],
        status: const Value('pending'),
        isSynced: const Value(true),
      ), mode: InsertMode.insertOrReplace);
    } catch (e) {
      print("Join request failed: $e");
      throw Exception(e.toString());
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

  Future<void> handleJoinRequest(String requestId, String status, {String? role}) async {
    try {
      final response = await dio.patch('$baseUrl/tours/requests/$requestId', data: {
        'status': status,
        'role': role ?? 'editor'
      });
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to handle request');
      }
    } catch (e) {
      print("Handle request failed: $e");
      throw Exception(e.toString());
    }
  }
}


