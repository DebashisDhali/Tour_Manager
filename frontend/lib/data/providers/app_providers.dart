import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:dio/dio.dart';
import '../local/app_database.dart';
import '../sync/sync_service.dart';
import '../services/auth_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final authService = ref.read(authServiceProvider);
      final token = await authService.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      return handler.next(options);
    },
  ));
  
  return dio;
});

final baseUrlProvider = Provider<String>((ref) => 'https://tour-manager-navy.vercel.app');

final authServiceProvider = Provider<AuthService>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = Dio();
  final baseUrl = ref.watch(baseUrlProvider);
  return AuthService(dio, db, baseUrl);
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = ref.watch(dioProvider);
  final baseUrl = ref.watch(baseUrlProvider);
  return SyncService(db, dio, baseUrl);
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
  return (db.select(db.tours)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();
});

final userListProvider = StreamProvider.autoDispose<List<User>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getAllUsers().asStream();
});

class MemberWithStatus {
  final User user;
  final String status;
  final String role;
  final DateTime? leftAt;
  final double mealCount;
  MemberWithStatus(this.user, this.status, this.role, this.leftAt, {this.mealCount = 0.0});
}

final tourMembersProvider = StreamProvider.family.autoDispose<List<MemberWithStatus>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.users).join([
    innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id)),
  ])..where(db.tourMembers.tourId.equals(tourId));
  
  return query.watch().map((rows) => rows.map((row) {
    final m = row.readTable(db.tourMembers);
    return MemberWithStatus(
      row.readTable(db.users),
      m.status,
      m.role,
      m.leftAt,
      mealCount: m.mealCount,
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
    if (otherPayers.length == 1) return otherPayers.first; // Should not happen if it's the same as payer
    
    // Check if payer is in otherPayers
    final uniqueNames = <String>{};
    if (payer != null) uniqueNames.add(payer!.name);
    uniqueNames.addAll(otherPayers);
    
    if (uniqueNames.length <= 1) return payer?.name ?? 'Unknown';
    if (uniqueNames.length == 2) return uniqueNames.join(' & ');
    return "${uniqueNames.first} + ${uniqueNames.length - 1} others";
  }
}

final expensesProvider = StreamProvider.family.autoDispose<List<ExpenseWithPayer>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  
  // 1. Watch expenses and primary payers
  final expenseQuery = db.select(db.expenses).join([
    leftOuterJoin(db.users, db.users.id.equalsExp(db.expenses.payerId)),
  ])..where(db.expenses.tourId.equals(tourId))
    ..orderBy([OrderingTerm.desc(db.expenses.createdAt)]);

  // 2. Watch all payers for this tour to match with expenses
  final payersQuery = db.select(db.expensePayers).join([
     innerJoin(db.expenses, db.expenses.id.equalsExp(db.expensePayers.expenseId)),
     innerJoin(db.users, db.users.id.equalsExp(db.expensePayers.userId)),
  ])..where(db.expenses.tourId.equals(tourId));

  // Combine them
  final expensesStream = expenseQuery.watch();
  final payersStream = payersQuery.watch();

  // We can't easily combine streams here without rxdart or custom logic
  // Let's use a simpler approach: fetch payers inside the mapping if possible
  // Actually, drift supports watching multiple tables.
  
  return expensesStream.map((rows) {
     return rows.map((row) {
        return ExpenseWithPayer(
          row.readTable(db.expenses),
          row.readTableOrNull(db.users),
        );
     }).toList();
  });
});

// Since combining streams in the provider is complex without rxdart, 
// I will instead provide a way to get the payers in the UI or update the provider to be a bit more "greedy"

final tourExpensesWithPayersProvider = StreamProvider.family.autoDispose<List<ExpenseWithPayer>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  
  // We'll watch three things: Expenses, ExpensePayers, and Users
  final expenses = db.select(db.expenses)..where((t) => t.tourId.equals(tourId));
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

final globalActivityProvider = StreamProvider.autoDispose<List<GlobalActivityItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return Stream.value([]);

  // Use a query that only returns expenses where the user is either the payer
  // OR is one of the people the expense is split with.
  final expenseQuery = db.select(db.expenses).join([
    leftOuterJoin(db.users, db.users.id.equalsExp(db.expenses.payerId)),
    innerJoin(db.tours, db.tours.id.equalsExp(db.expenses.tourId)),
  ])..where(
    db.expenses.payerId.equals(currentUser.id) |
    db.expenses.id.isInQuery(db.selectOnly(db.expenseSplits)..addColumns([db.expenseSplits.expenseId])..where(db.expenseSplits.userId.equals(currentUser.id)))
  );

  return expenseQuery.watch().map((rows) {
    final items = rows.map((row) {
      final e = row.readTable(db.expenses);
      return GlobalActivityItem(
        type: 'expense',
        item: e,
        user: row.readTableOrNull(db.users),
        tour: row.readTable(db.tours),
        date: e.createdAt,
        amount: e.amount,
      );
    }).toList();
    
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  });
});

final singleTourProvider = StreamProvider.family.autoDispose<Tour, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tours)..where((t) => t.id.equals(tourId))).watchSingle();
});

final singleUserProvider = StreamProvider.family.autoDispose<User?, String>((ref, userId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)..where((u) => u.id.equals(userId))).watchSingleOrNull();
});
final tourUsersProvider = StreamProvider.family.autoDispose<List<User>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.users).join([
    innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id)),
  ])..where(db.tourMembers.tourId.equals(tourId));
  return query.watch().map((rows) => rows.map((row) => row.readTable(db.users)).toList());
});

final tourExpensesProvider = StreamProvider.family.autoDispose<List<Expense>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.expenses)..where((t) => t.tourId.equals(tourId))).watch();
});

final tourSplitsProvider = StreamProvider.family.autoDispose<List<ExpenseSplit>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expenseSplits).join([
    innerJoin(db.expenses, db.expenses.id.equalsExp(db.expenseSplits.expenseId)),
  ])..where(db.expenses.tourId.equals(tourId));
  return query.watch().map((rows) => rows.map((row) => row.readTable(db.expenseSplits)).toList());
});

final tourPayersProvider = StreamProvider.family.autoDispose<List<ExpensePayer>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expensePayers).join([
    innerJoin(db.expenses, db.expenses.id.equalsExp(db.expensePayers.expenseId)),
  ])..where(db.expenses.tourId.equals(tourId));
  return query.watch().map((rows) => rows.map((row) => row.readTable(db.expensePayers)).toList());
});

final tourSettlementsProvider = StreamProvider.family.autoDispose<List<Settlement>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.settlements)..where((t) => t.tourId.equals(tourId))).watch();
});

final tourIncomesProvider = StreamProvider.family.autoDispose<List<ProgramIncome>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.programIncomes)..where((t) => t.tourId.equals(tourId))).watch();
});

final tourMealRecordsProvider = StreamProvider.family.autoDispose<List<MealRecord>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return db.watchMealRecords(tourId);
});

final lastSyncProvider = StreamProvider.family.autoDispose<String?, String>((ref, userId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncMetadata)..where((t) => t.key.equals('last_sync_$userId')))
      .watchSingleOrNull()
      .map((row) => row?.value);
});
