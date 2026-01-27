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
    if (kDebugMode) {
      if (kIsWeb) {
        return 'http://127.0.0.1:3000';
      } else {
        // If it's an emulator, it can use local. 
        // But for real devices, we must use the production server
        // so it works on any network (mobile data/different Wi-Fi).
        return Platform.isAndroid ? 'https://tourmanager-production-fbbd.up.railway.app' : 'http://localhost:3000';
      }
    }
    // Final fallback for production/release mode
    return 'https://tourmanager-production-fbbd.up.railway.app';
  }

  SyncService(this.db, this.dio) {
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    
    dio.interceptors.add(LogInterceptor(
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
      
      // 1. Gather Unsynced Data
      final unsyncedUsers = await db.getUnsyncedUsers();
      final unsyncedTours = await db.getUnsyncedTours();
      final unsyncedExpenses = await db.getUnsyncedExpenses();
      final unsyncedSplits = await db.getUnsyncedSplits();
      final unsyncedPayers = await db.getUnsyncedExpensePayers();
      final unsyncedSettlements = await db.getUnsyncedSettlements();

      if (unsyncedUsers.isEmpty && unsyncedTours.isEmpty && unsyncedExpenses.isEmpty && unsyncedSplits.isEmpty && unsyncedPayers.isEmpty && unsyncedSettlements.isEmpty) {
        // Still pull
      }

      final response = await dio.post('$baseUrl/sync', data: {
        'userId': userId,
        'unsyncedData': {
          'users': unsyncedUsers.map((u) => {
            'id': u.id, 
            'name': u.name, 
            'phone': u.phone,
            'email': u.email,
            'avatarUrl': u.avatarUrl,
            'purpose': u.purpose
          }).toList(),
          'tours': unsyncedTours.map((t) => {
            'id': t.id, 
            'name': t.name, 
            'createdBy': t.createdBy,
            'inviteCode': t.inviteCode,
            'startDate': t.startDate?.toIso8601String(),
            'endDate': t.endDate?.toIso8601String(),
          }).toList(),
          'expenses': unsyncedExpenses.map((e) => {
            'id': e.id,
            'tourId': e.tourId,
            'payerId': e.payerId,
            'amount': e.amount,
            'title': e.title,
            'category': e.category,
            'createdAt': e.createdAt.toIso8601String(),
          }).toList(),
          'splits': unsyncedSplits.map((s) => {
            'id': s.id,
            'userId': s.userId,
            'amount': s.amount,
          }).toList(),
          'payers': unsyncedPayers.map((p) => {
            'id': p.id,
            'expenseId': p.expenseId,
            'userId': p.userId,
            'amount': p.amount,
          }).toList(),
          'settlements': unsyncedSettlements.map((s) => {
            'id': s.id,
            'tourId': s.tourId,
            'fromId': s.fromId,
            'toId': s.toId,
            'amount': s.amount,
            'date': s.date.toIso8601String(),
          }).toList(),
        }
      });

      if (response.statusCode == 200) {
        // Mark as synced locally
        for (final u in unsyncedUsers) await db.markUserSynced(u.id);
        for (final t in unsyncedTours) await db.markTourSynced(t.id);
        for (final e in unsyncedExpenses) await db.markExpenseSynced(e.id);
        for (final s in unsyncedSplits) await db.markSplitSynced(s.id);
        for (final p in unsyncedPayers) await db.markExpensePayerSynced(p.id);
        for (final s in unsyncedSettlements) await db.markSettlementSynced(s.id);

        // 2. Process Pulled Data (Tours, Members, Expenses)
        final serverTours = response.data['tours'] as List;
        for (final st in serverTours) {
          // Sync Tour
          await db.createTour(Tour(
            id: st['id'],
            name: st['name'],
            startDate: st['start_date'] != null ? DateTime.parse(st['start_date']) : null,
            endDate: st['end_date'] != null ? DateTime.parse(st['end_date']) : null,
            inviteCode: st['invite_code'],
            createdBy: st['created_by'],
            isSynced: true,
            updatedAt: DateTime.now(),
          ));

          // Sync Members
          if (st['Users'] != null) {
             for (final su in st['Users']) {
               await db.createUser(User(
                 id: su['id'],
                 name: su['name'],
                 phone: su['phone'],
                 email: su['email'],
                 avatarUrl: su['avatar_url'],
                 purpose: su['purpose'],
                 isMe: su['id'] == userId,
                 isSynced: true,
                 updatedAt: DateTime.now(),
               ));
               // Add connection
               await db.into(db.tourMembers).insert(TourMember(
                 tourId: st['id'],
                 userId: su['id'],
                 isSynced: true,
               ), mode: InsertMode.insertOrIgnore);
             }
          }

          // Sync Expenses
          if (st['Expenses'] != null) {
            for (final se in st['Expenses']) {
              await db.into(db.expenses).insert(Expense(
                id: se['id'],
                tourId: st['id'],
                payerId: se['payer_id'],
                amount: (se['amount'] as num).toDouble(),
                title: se['title'],
                category: se['category'],
                isSynced: true,
                createdAt: DateTime.parse(se['date']),
              ), mode: InsertMode.insertOrReplace);

              // Sync Splits
              if (se['ExpenseSplits'] != null) {
                for (final ss in se['ExpenseSplits']) {
                  await db.into(db.expenseSplits).insert(ExpenseSplit(
                    id: ss['id'] ?? const Uuid().v4(),
                    expenseId: se['id'],
                    userId: ss['user_id'],
                    amount: (ss['amount'] as num).toDouble(),
                    isSynced: true,
                  ), mode: InsertMode.insertOrReplace);
                }
              }

              // Sync Payers
              if (se['ExpensePayers'] != null) {
                for (final sp in se['ExpensePayers']) {
                  await db.into(db.expensePayers).insert(ExpensePayer(
                    id: sp['id'] ?? const Uuid().v4(),
                    expenseId: se['id'],
                    userId: sp['user_id'],
                    amount: (sp['amount'] as num).toDouble(),
                    isSynced: true,
                  ), mode: InsertMode.insertOrReplace);
                }
              }
            }
          }

          // Sync Settlements
          final settlements = st['Settlements'] ?? st['settlements'];
          if (settlements != null && settlements is List) {
             for (final ss in settlements) {
               try {
                 final fromId = (ss['from_id'] ?? ss['fromId'] ?? '').toString();
                 final toId = (ss['to_id'] ?? ss['toId'] ?? '').toString();
                 if (fromId.isEmpty || toId.isEmpty) continue;

                 await db.into(db.settlements).insert(Settlement(
                   id: (ss['id'] ?? '').toString(),
                   tourId: (st['id'] ?? '').toString(),
                   fromId: fromId,
                   toId: toId,
                   amount: double.tryParse(ss['amount']?.toString() ?? '0') ?? 0.0,
                   date: ss['date'] != null ? DateTime.parse(ss['date'].toString()) : DateTime.now(),
                   isSynced: true,
                 ), mode: InsertMode.insertOrReplace);
               } catch (e) { print("Error syncing settlement: $e"); }
             }
          }
        }
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
                  
                  await db.createUser(User(
                    id: mId,
                    name: (member['name'] ?? 'Unknown').toString(),
                    phone: member['phone']?.toString(),
                    email: member['email']?.toString(),
                    avatarUrl: (member['avatar_url'] ?? member['avatarUrl'])?.toString(),
                    purpose: (member['purpose'] ?? 'tour').toString(),
                    isMe: mId == userId,
                    isSynced: true,
                    updatedAt: DateTime.now(),
                  ));
                  
                  await db.into(db.tourMembers).insert(TourMember(
                    tourId: tourData['id'].toString(),
                    userId: mId,
                    isSynced: true,
                  ), mode: InsertMode.insertOrIgnore);
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
}


