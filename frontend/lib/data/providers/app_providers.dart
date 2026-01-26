import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:dio/dio.dart';
import '../local/app_database.dart';
import '../sync/sync_service.dart';
import '../../main.dart';

final dioProvider = Provider<Dio>((ref) => Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 60),
  receiveTimeout: const Duration(seconds: 60),
)));

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = ref.watch(dioProvider);
  return SyncService(db, dio);
});

final currentUserProvider = StreamProvider<User?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)
        ..orderBy([(u) => OrderingTerm.desc(u.isMe)])
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
  final DateTime? leftAt;
  MemberWithStatus(this.user, this.leftAt);
}

final tourMembersProvider = StreamProvider.family.autoDispose<List<MemberWithStatus>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.users).join([
    innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id)),
  ])..where(db.tourMembers.tourId.equals(tourId));
  
  return query.watch().map((rows) => rows.map((row) => MemberWithStatus(
    row.readTable(db.users),
    row.readTable(db.tourMembers).leftAt,
  )).toList());
});

class ExpenseWithPayer {

  final Expense expense;
  final User payer;
  ExpenseWithPayer(this.expense, this.payer);
}

final expensesProvider = StreamProvider.family.autoDispose<List<ExpenseWithPayer>, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expenses).join([
    innerJoin(db.users, db.users.id.equalsExp(db.expenses.payerId)),
  ])..where(db.expenses.tourId.equals(tourId))
    ..orderBy([OrderingTerm.desc(db.expenses.createdAt)]);

  return query.watch().map((rows) => rows.map((row) {
    return ExpenseWithPayer(
      row.readTable(db.expenses),
      row.readTable(db.users),
    );
  }).toList());
});class GlobalExpenseItem {
  final Expense expense;
  final User payer;
  final Tour tour;
  GlobalExpenseItem(this.expense, this.payer, this.tour);
}

final globalRecentExpensesProvider = StreamProvider.autoDispose<List<GlobalExpenseItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.expenses).join([
    innerJoin(db.users, db.users.id.equalsExp(db.expenses.payerId)),
    innerJoin(db.tours, db.tours.id.equalsExp(db.expenses.tourId)),
  ])..orderBy([OrderingTerm.desc(db.expenses.createdAt)])
    ..limit(20);

  return query.watch().map((rows) => rows.map((row) {
    return GlobalExpenseItem(
      row.readTable(db.expenses),
      row.readTable(db.users),
      row.readTable(db.tours),
    );
  }).toList());
});
final singleTourProvider = StreamProvider.family.autoDispose<Tour, String>((ref, tourId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tours)..where((t) => t.id.equals(tourId))).watchSingle();
});



