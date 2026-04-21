import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local/app_database.dart';
import '../sync/sync_service.dart';
import '../services/auth_service.dart';
import '../services/ai_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 120),
    receiveTimeout: const Duration(seconds: 120),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');

        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
          debugPrint("🔑 Auth Interceptor: Token attached to ${options.path}");
        } else {
          debugPrint("⚠️ Auth Interceptor: No token found for ${options.path}");
        }
      } catch (e) {
        debugPrint("❌ Auth Interceptor Error: $e");
      }
      return handler.next(options);
    },
    onError: (error, handler) {
      final status = error.response?.statusCode;
      final path = error.requestOptions.path;
      final method = error.requestOptions.method;
      final data = error.response?.data;
      final serverMsg = data is Map
          ? (data['message'] ?? data['error'] ?? '').toString()
          : '';

      final statusPart = status != null ? ' [HTTP $status]' : '';
      final serverPart = serverMsg.isNotEmpty ? ' | server: $serverMsg' : '';
      debugPrint(
          '❌ Dio Error$statusPart $method $path (type: ${error.type})$serverPart');

      return handler.next(error);
    },
  ));

  return dio;
});

final baseUrlProvider =
    Provider<String>((ref) => 'https://tour-manager-navy.vercel.app');

final authServiceProvider = Provider<AuthService>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 120),
    receiveTimeout: const Duration(seconds: 120),
  ));
  final baseUrl = ref.watch(baseUrlProvider);
  return AuthService(dio, db, baseUrl);
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = ref.watch(dioProvider); // ← uses the authenticated Dio instance
  final baseUrl = ref.watch(baseUrlProvider);
  return SyncService(db, dio, baseUrl);
});

final aiServiceProvider = Provider<AiService>((ref) {
  final dio = ref.watch(dioProvider);
  final baseUrl = ref.watch(baseUrlProvider);
  return AiService(dio, baseUrl);
});

final currentUserProvider = StreamProvider<User?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)
        ..where((u) => u.isMe.equals(true))
        ..limit(1))
      .watchSingleOrNull();
});

final tourListProvider = StreamProvider.autoDispose<List<Tour>>((ref) {
  final db = ref.watch(databaseProvider);
  final currentUser = ref.watch(currentUserProvider).value;

  if (currentUser == null) return Stream.value([]);

  final query = db.select(db.tours).join([
    innerJoin(db.tourMembers, db.tourMembers.tourId.equalsExp(db.tours.id)),
  ])
    ..where(db.tourMembers.userId.lower().equals(currentUser.id.toLowerCase()) &
        db.tourMembers.status.equals('active') &
        db.tourMembers.isDeleted.equals(false) &
        db.tours.isDeleted.equals(false));

  return query.watch().map((rows) {
    final uniqueTours = <String, Tour>{};
    for (final row in rows) {
      final tour = row.readTable(db.tours);
      uniqueTours[tour.id] = tour;
    }
    final deduped = uniqueTours.values.toList()
      ..sort((a, b) {
        // Sort by startDate descending (newer first), then by ID
        if (a.startDate != null && b.startDate != null) {
          final byTime = b.startDate!.compareTo(a.startDate!);
          if (byTime != 0) return byTime;
        }
        return a.id.compareTo(b.id);
      });
    return deduped;
  }).distinct((previous, next) {
    if (previous.length != next.length) return false;
    for (int i = 0; i < previous.length; i++) {
      final p = previous[i];
      final n = next[i];
      if (p.id != n.id ||
          p.isSynced != n.isSynced ||
          p.isDeleted != n.isDeleted) {
        return false;
      }
    }
    return true;
  });
});

final userListProvider = StreamProvider.autoDispose<List<User>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getAllUsers().asStream();
});

class MemberWithStatus {
  final User user;
  final String status; // 'active', 'pending', 'removed'
  final String role; // 'admin', 'editor', 'viewer'
  final DateTime? leftAt;
  final double mealCount;
  final String? addedBy; // New: tracks who added this member

  MemberWithStatus(
    this.user,
    this.status,
    this.role,
    this.leftAt, {
    this.mealCount = 0.0,
    this.addedBy,
  });
}

final tourMembersProvider = StreamProvider.family
    .autoDispose<List<MemberWithStatus>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.users).join([
    innerJoin(db.tourMembers, db.tourMembers.userId.lower().equalsExp(db.users.id.lower())),
  ])
    ..where(db.tourMembers.tourId.equals(tourId) &
        db.tourMembers.isDeleted.equals(false) &
        db.users.isDeleted.equals(false));

  return query.watch().map((rows) => rows.map((row) {
        final m = row.readTable(db.tourMembers);
        final normalizedRole = m.role.toLowerCase().trim();
        final normalizedStatus = m.status.toLowerCase().trim();
        return MemberWithStatus(
          row.readTable(db.users),
          normalizedStatus,
          normalizedRole,
          m.leftAt,
          mealCount: m.mealCount,
          addedBy: null, // Initialize from DB when you have addedBy field
        );
      }).toList());
});

class ExpenseWithPayer {
  final Expense expense;
  final User? payer;
  final List<String> otherPayers;
  ExpenseWithPayer(this.expense, this.payer, {this.otherPayers = const []});

  String get payerNames {
    if (otherPayers.isEmpty) return payer?.name ?? 'Unknown';
    if (otherPayers.length == 1) {
      return otherPayers.first; // Should not happen if it's the same as payer
    }

    // Check if payer is in otherPayers
    final uniqueNames = <String>{};
    if (payer != null) uniqueNames.add(payer!.name);
    uniqueNames.addAll(otherPayers);

    if (uniqueNames.length <= 1) return payer?.name ?? 'Unknown';
    if (uniqueNames.length == 2) return uniqueNames.join(' & ');
    return "${uniqueNames.first} + ${uniqueNames.length - 1} others";
  }
}

final expensesProvider = StreamProvider.family
    .autoDispose<List<ExpenseWithPayer>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);

  final expenseQuery = db.select(db.expenses).join([
    leftOuterJoin(db.users, db.users.id.lower().equalsExp(db.expenses.payerId.lower())),
  ])
    ..where(
        db.expenses.tourId.equals(tourId) & db.expenses.isDeleted.equals(false))
    ..orderBy([OrderingTerm.desc(db.expenses.createdAt)]);

  return expenseQuery.watch().map((rows) {
    final uniqueByExpenseId = <String, ExpenseWithPayer>{};

    for (final row in rows) {
      try {
        final expenseWithPayer = ExpenseWithPayer(
          row.readTable(db.expenses),
          row.readTableOrNull(db.users),
        );
        uniqueByExpenseId[expenseWithPayer.expense.id] = expenseWithPayer;
      } catch (e) {
        debugPrint(
            "\n\n🧨 FATAL ERROR MAPPING EXPENSES PROVIDER ROW: ${row.rawData.data}\n\n");
        rethrow;
      }
    }

    return uniqueByExpenseId.values.toList();
  }).distinct((previous, next) {
    // Prevent duplicate emissions by comparing list lengths and IDs
    if (previous.length != next.length) return false;
    for (int i = 0; i < previous.length; i++) {
      if (previous[i].expense.id != next[i].expense.id) return false;
    }
    return true;
  });
});

// Since combining streams in the provider is complex without rxdart,
// I will instead provide a way to get the payers in the UI or update the provider to be a bit more "greedy"

final tourExpensesWithPayersProvider = StreamProvider.family
    .autoDispose<List<ExpenseWithPayer>, String>((ref, tourId) {
  // This is still hard without CombineLatest.
  // Let's just update the UI to use the existing tourPayersProvider.
  return ref.watch(expensesProvider(tourId).stream);
});

class GlobalActivityItem {
  final String type; // 'expense', 'income', 'settlement'
  final dynamic item;
  final User? user; // Payer, Collector, or FromUser
  final Tour tour;
  final DateTime date;
  final double amount;

  GlobalActivityItem({
    required this.type,
    required this.item,
    this.user,
    required this.tour,
    required this.date,
    required this.amount,
  });
}

final globalActivityProvider =
    StreamProvider.autoDispose<List<GlobalActivityItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return Stream.value([]);

  final activeTourIdsQuery = db.selectOnly(db.tourMembers)
    ..addColumns([db.tourMembers.tourId])
    ..where(db.tourMembers.userId
            .lower()
            .equals(currentUser.id.toLowerCase()) &
        db.tourMembers.status.equals('active') &
        db.tourMembers.isDeleted.equals(false));

  final expenseQuery = db.select(db.expenses).join([
    leftOuterJoin(db.users, db.users.id.lower().equalsExp(db.expenses.payerId.lower())),
    innerJoin(db.tours, db.tours.id.equalsExp(db.expenses.tourId)),
  ])
    ..where(db.expenses.isDeleted.equals(false) &
        db.tours.isDeleted.equals(false) &
        db.expenses.tourId.isInQuery(activeTourIdsQuery));

  return expenseQuery.watch().map((rows) {
    try {
      final items = rows.map((row) {
        try {
          final e = row.readTable(db.expenses);
          return GlobalActivityItem(
            type: 'expense',
            item: e,
            user: row.readTableOrNull(db.users),
            tour: row.readTable(db.tours),
            date: e.createdAt,
            amount: e.amount,
          );
        } catch (mapErr) {
          debugPrint(
              "\n\n🧨 FATAL ERROR MAPPING GLOBAL ACTIVITY ROW: ${row.rawData.data}\n\n");
          rethrow;
        }
      }).toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    } catch (e) {
      debugPrint(
          "\n\n🧨 FATAL ERROR IN GLOBAL ACTIVITY PROVIDER LISTENER: $e\n\n");
      rethrow;
    }
  });
});

final singleTourProvider =
    StreamProvider.family.autoDispose<Tour?, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tours)..where((t) => t.id.equals(tourId)))
      .watchSingleOrNull()
      .handleError((e) {
    debugPrint("\n\n🧨 FATAL ERROR MAPPING SINGLE TOUR [$tourId]: $e\n\n");
  });
});

final singleUserProvider =
    StreamProvider.family.autoDispose<User?, String>((ref, userId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)..where((u) => u.id.equals(userId)))
      .watchSingleOrNull();
});

final tourUsersProvider =
    StreamProvider.family.autoDispose<List<User>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.users).join([
    innerJoin(db.tourMembers, db.tourMembers.userId.lower().equalsExp(db.users.id.lower())),
  ])
    ..where(db.tourMembers.tourId.equals(tourId) &
        db.tourMembers.status.equals('active') &
        db.tourMembers.isDeleted.equals(false) &
        db.users.isDeleted.equals(false));
  return query
      .watch()
      .map((rows) => rows.map((row) {
            try {
              return row.readTable(db.users);
            } catch (e) {
              debugPrint(
                  "\n\n🧨 FATAL ERROR MAPPING TOUR USER: ${row.rawData.data}\n\n");
              rethrow;
            }
          }).toList())
      .map((users) {
    final unique = <String, User>{};
    for (final u in users) {
      unique[u.id] = u;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return deduped;
  });
});

final tourExpensesProvider =
    StreamProvider.family.autoDispose<List<Expense>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.expenses)
        ..where((t) => t.tourId.equals(tourId) & t.isDeleted.equals(false)))
      .watch()
      .handleError((e) {
    debugPrint("\n\n🧨 FATAL ERROR MAPPING TOUR EXPENSES: $e\n\n");
  });
});

final tourSplitsProvider = StreamProvider.family
    .autoDispose<List<ExpenseSplit>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expenseSplits).join([
    innerJoin(
        db.expenses, db.expenses.id.equalsExp(db.expenseSplits.expenseId)),
  ])
    ..where(db.expenses.tourId.equals(tourId) &
        db.expenses.isDeleted.equals(false) &
        db.expenseSplits.isDeleted.equals(false));
  return query.watch().map(
      (rows) => rows.map((row) => row.readTable(db.expenseSplits)).toList());
});

final tourPayersProvider = StreamProvider.family
    .autoDispose<List<ExpensePayer>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expensePayers).join([
    innerJoin(
        db.expenses, db.expenses.id.equalsExp(db.expensePayers.expenseId)),
  ])
    ..where(db.expenses.tourId.equals(tourId) &
        db.expenses.isDeleted.equals(false) &
        db.expensePayers.isDeleted.equals(false));
  return query.watch().map(
      (rows) => rows.map((row) => row.readTable(db.expensePayers)).toList());
});

final tourSettlementsProvider =
    StreamProvider.family.autoDispose<List<Settlement>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.settlements)
        ..where((t) => t.tourId.equals(tourId) & t.isDeleted.equals(false)))
      .watch();
});

final tourIncomesProvider = StreamProvider.family
    .autoDispose<List<ProgramIncome>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.programIncomes)
        ..where((t) => t.tourId.equals(tourId) & t.isDeleted.equals(false)))
      .watch();
});

final tourMealRecordsProvider =
    StreamProvider.family.autoDispose<List<MealRecord>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return db.watchMealRecords(tourId);
});

final lastSyncProvider =
    StreamProvider.family.autoDispose<String?, String>((ref, userId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncMetadata)
        ..where((t) => t.key.equals('last_sync_$userId')))
      .watchSingleOrNull()
      .map((row) => row?.value);
});

final hasUnsyncedChangesProvider = StreamProvider.autoDispose<bool>((ref) {
  final db = ref.watch(databaseProvider);

  // Create a stream that emits whenever ANY of the tables changes
  // We can merge them or just watch a few primary ones.
  // In our case, syncing is cheap enough that we can just watch the counts.

  final toursStream =
      (db.select(db.tours)..where((x) => x.isSynced.equals(false))).watch();
  final expensesStream =
      (db.select(db.expenses)..where((x) => x.isSynced.equals(false))).watch();
  final settlementsStream = (db.select(db.settlements)
        ..where((x) => x.isSynced.equals(false)))
      .watch();

  // Combine multiple streams manually for auto-sync trigger
  final controller = StreamController<bool>();

  bool hasTours = false;
  bool hasExpenses = false;
  bool hasSettlements = false;

  void emit() {
    if (!controller.isClosed) {
      controller.add(hasTours || hasExpenses || hasSettlements);
    }
  }

  final sub1 = toursStream.listen((l) {
    hasTours = l.isNotEmpty;
    emit();
  });
  final sub2 = expensesStream.listen((l) {
    hasExpenses = l.isNotEmpty;
    emit();
  });
  final sub3 = settlementsStream.listen((l) {
    hasSettlements = l.isNotEmpty;
    emit();
  });

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    sub3.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Pairs a JoinRequest record with its corresponding Tour (may be null if tour
/// not yet in local DB).
class JoinRequestWithTour {
  final JoinRequest request;
  final Tour? tour;
  JoinRequestWithTour(this.request, this.tour);
}

/// Streams ALL join_requests that were created by the CURRENT USER (any status),
/// joined with the relevant tour row so callers can show tour names.
final myJoinRequestsProvider =
    StreamProvider.autoDispose<List<JoinRequestWithTour>>((ref) {
  final db = ref.watch(databaseProvider);
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return Stream.value([]);

  return (db.select(db.joinRequests).join([
    leftOuterJoin(db.tours, db.tours.id.equalsExp(db.joinRequests.tourId)),
  ])
        ..where(db.joinRequests.userId
                .lower()
                .equals(currentUser.id.toLowerCase()) &
            db.joinRequests.isDeleted.equals(false)))
      .watch()
      .map((rows) => rows
          .map((row) => JoinRequestWithTour(
                row.readTable(db.joinRequests),
                row.readTableOrNull(db.tours),
              ))
          .toList());
});

final myJoinRequestForTourProvider =
    StreamProvider.family.autoDispose<JoinRequest?, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return Stream.value(null);

  return (db.select(db.joinRequests)
        ..where((jr) =>
            jr.tourId.equals(tourId) &
            jr.userId.lower().equals(currentUser.id.toLowerCase()) &
            jr.isDeleted.equals(false))
        ..orderBy([(jr) => OrderingTerm.desc(jr.id)])
        ..limit(1))
      .watchSingleOrNull();
});

/// Streams ALL tours where the current user is invited but hasn't yet accepted 
/// (status is 'pending'). This is used for notification badges.
final myIncomingInvitationsProvider = StreamProvider.autoDispose<List<Tour>>((ref) {
  final db = ref.watch(databaseProvider);
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return Stream.value([]);

  final query = db.select(db.tours).join([
    innerJoin(db.tourMembers, db.tourMembers.tourId.equalsExp(db.tours.id)),
  ])
    ..where(db.tourMembers.userId.lower().equals(currentUser.id.toLowerCase()) &
        db.tourMembers.status.equals('pending') &
        db.tourMembers.isDeleted.equals(false) &
        db.tours.isDeleted.equals(false));

  return query.watch().map((rows) => rows.map((row) => row.readTable(db.tours)).toList());
});
