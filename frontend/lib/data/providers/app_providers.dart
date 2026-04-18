import 'dart:async';
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
          print("🔑 Auth Interceptor: Token attached to ${options.path}");
        } else {
          print("⚠️ Auth Interceptor: No token found for ${options.path}");
        }
      } catch (e) {
        print("❌ Auth Interceptor Error: $e");
      }
      return handler.next(options);
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
        ..orderBy([(u) => OrderingTerm.desc(u.updatedAt)])
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
        db.tours.isDeleted.equals(false))
    ..orderBy([OrderingTerm.desc(db.tours.updatedAt)]);

  return query
      .watch()
      .map((rows) => rows.map((row) => row.readTable(db.tours)).toList());
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
    innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id)),
  ])
    ..where(db.tourMembers.tourId.equals(tourId));

  return query.watch().map((rows) => rows.map((row) {
        final m = row.readTable(db.tourMembers);
        return MemberWithStatus(
          row.readTable(db.users),
          m.status,
          m.role,
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
    if (otherPayers.length == 1)
      return otherPayers.first; // Should not happen if it's the same as payer

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

  // Only show expenses from active members and editors/admins (not viewer-only)
  final expenseQuery = db.select(db.expenses).join([
    leftOuterJoin(db.users, db.users.id.equalsExp(db.expenses.payerId)),
    innerJoin(
        db.tourMembers, db.tourMembers.tourId.equalsExp(db.expenses.tourId)),
  ])
    ..where(db.expenses.tourId.equals(tourId) &
        db.expenses.isDeleted.equals(false) &
        (db.tourMembers.role.equals('admin') |
            db.tourMembers.role.equals('editor') |
            db.tourMembers.role.equals('viewer')))
    ..orderBy([OrderingTerm.desc(db.expenses.createdAt)]);

  return expenseQuery.watch().map((rows) {
    return rows.map((row) {
      try {
        return ExpenseWithPayer(
          row.readTable(db.expenses),
          row.readTableOrNull(db.users),
        );
      } catch (e) {
        print(
            "\n\n🧨 FATAL ERROR MAPPING EXPENSES PROVIDER ROW: ${row.rawData.data}\n\n");
        rethrow;
      }
    }).toList();
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
  final db = ref.watch(databaseProvider);

  // We'll watch three things: Expenses, ExpensePayers, and Users
  final expenses = db.select(db.expenses)
    ..where((t) => t.tourId.equals(tourId));
  final payers = db.select(db.expensePayers).join([
    innerJoin(db.users, db.users.id.equalsExp(db.expensePayers.userId)),
  ]);

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

  final expenseQuery = db.select(db.expenses).join([
    leftOuterJoin(db.users, db.users.id.equalsExp(db.expenses.payerId)),
    innerJoin(db.tours, db.tours.id.equalsExp(db.expenses.tourId)),
  ])
    ..where(db.expenses.isDeleted.equals(false) &
        (db.expenses.payerId.equals(currentUser.id) |
            db.expenses.id.isInQuery(db.selectOnly(db.expenseSplits)
              ..addColumns([db.expenseSplits.expenseId])
              ..where(db.expenseSplits.userId.equals(currentUser.id)))));

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
          print(
              "\n\n🧨 FATAL ERROR MAPPING GLOBAL ACTIVITY ROW: ${row.rawData.data}\n\n");
          rethrow;
        }
      }).toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    } catch (e) {
      print("\n\n🧨 FATAL ERROR IN GLOBAL ACTIVITY PROVIDER LISTENER: $e\n\n");
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
    print("\n\n🧨 FATAL ERROR MAPPING SINGLE TOUR [$tourId]: $e\n\n");
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
    innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id)),
  ])
    ..where(db.tourMembers.tourId.equals(tourId));
  return query.watch().map((rows) => rows.map((row) {
        try {
          return row.readTable(db.users);
        } catch (e) {
          print(
              "\n\n🧨 FATAL ERROR MAPPING TOUR USER: ${row.rawData.data}\n\n");
          rethrow;
        }
      }).toList());
});

final tourExpensesProvider =
    StreamProvider.family.autoDispose<List<Expense>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.expenses)
        ..where((t) => t.tourId.equals(tourId) & t.isDeleted.equals(false)))
      .watch()
      .handleError((e) {
    print("\n\n🧨 FATAL ERROR MAPPING TOUR EXPENSES: $e\n\n");
  });
});

final tourSplitsProvider = StreamProvider.family
    .autoDispose<List<ExpenseSplit>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expenseSplits).join([
    innerJoin(
        db.expenses, db.expenses.id.equalsExp(db.expenseSplits.expenseId)),
  ])
    ..where(db.expenses.tourId.equals(tourId));
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
    ..where(db.expenses.tourId.equals(tourId));
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
