import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:uuid/uuid.dart';

class SyncService {
  final AppDatabase db;
  final Dio dio;
  
  String get baseUrl {
    return 'https://tourmanager-production-fbbd.up.railway.app';
  }

  SyncService(this.db, this.dio) {
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        // startSync(userId); // Needs userId from context outside
      }
    });
  }

  Future<void> startSync(String userId) async {
    try {
      print("Sync started for user: $userId");
      
      // 1. Gather Unsynced Data
      final unsyncedUsers = await db.getUnsyncedUsers();
      final unsyncedTours = await db.getUnsyncedTours();
      final unsyncedExpenses = await db.getUnsyncedExpenses();
      final unsyncedSplits = await db.getUnsyncedSplits();

      if (unsyncedUsers.isEmpty && unsyncedTours.isEmpty && unsyncedExpenses.isEmpty && unsyncedSplits.isEmpty) {
        // Maybe still pull
      }

      final response = await dio.post('$baseUrl/sync', data: {
        'userId': userId,
        'unsyncedData': {
          'users': unsyncedUsers.map((u) => {'id': u.id, 'name': u.name, 'phone': u.phone}).toList(),
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
            'expenseId': s.expenseId,
            'userId': s.userId,
            'amount': s.amount,
          }).toList(),
        }
      });

      if (response.statusCode == 200) {
        // Mark as synced locally
        for (final u in unsyncedUsers) await db.markUserSynced(u.id);
        for (final t in unsyncedTours) await db.markTourSynced(t.id);
        for (final e in unsyncedExpenses) await db.markExpenseSynced(e.id);
        for (final s in unsyncedSplits) await db.markSplitSynced(s.id);

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
                 isMe: false,
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
                    id: ss['id'] ?? const Uuid().v4(), // Fallback if backend doesn't send ID
                    expenseId: se['id'],
                    userId: ss['user_id'],
                    amount: (ss['amount'] as num).toDouble(),
                    isSynced: true,
                  ), mode: InsertMode.insertOrReplace);
                }
              }
            }
          }
        }
      }
      print("Sync completed.");
    } catch (e) {
      print("Sync failed: $e");
    }
  }

  Future<void> joinByInvite(String inviteCode, String userId, String userName) async {
    try {
      final response = await dio.post('$baseUrl/tours/join', data: {
        'invite_code': inviteCode,
        'user_id': userId,
        'user_name': userName
      });
      
      if (response.statusCode == 200) {
        print("Joined successfully on server. Response: ${response.data}");
        
        // Trigger sync to get the new tour data immediately
        try {
          print("Starting post-join sync...");
          await startSync(userId);
          print("Post-join sync completed successfully.");
        } catch (syncError) {
          print("Post-join sync failed: $syncError");
          // Re-throw so the UI knows there was an issue, 
          // even if the join itself succeeded on server.
          throw Exception("Joined group, but failed to download data. Try manual sync. ($syncError)");
        }
      } else {
        throw Exception("Server returned ${response.statusCode}: ${response.data}");
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? e.message;
      print("Join failed (DioError): $msg");
      throw Exception(msg);
    } catch (e) {
      print("Join failed (Generic): $e");
      rethrow;
    }
  }
}


