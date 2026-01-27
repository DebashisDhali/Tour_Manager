import 'package:drift/drift.dart';
import 'connection/connection.dart';

part 'app_database.g.dart';

// Tables
class Users extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get purpose => text().nullable()(); // 'tour', 'mess', 'event', 'business'
  BoolColumn get isMe => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {id};
}

class Tours extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get inviteCode => text().nullable()();
  TextColumn get createdBy => text()(); // User ID
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TourMembers extends Table {
  TextColumn get tourId => text().references(Tours, #id)();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get leftAt => dateTime().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  
  @override
  Set<Column> get primaryKey => {tourId, userId};
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get tourId => text().references(Tours, #id)();
  TextColumn get payerId => text().named('payer_id').nullable().references(Users, #id)();
  RealColumn get amount => real()();
  TextColumn get title => text()();
  TextColumn get category => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  
  @override
  Set<Column> get primaryKey => {id};
}

class ExpenseSplits extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text().references(Expenses, #id)();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get amount => real()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ExpensePayers extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text().references(Expenses, #id)();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get amount => real()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Settlements extends Table {
  TextColumn get id => text()();
  TextColumn get tourId => text().references(Tours, #id)();
  TextColumn get fromId => text().references(Users, #id)();
  TextColumn get toId => text().references(Users, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Users, Tours, TourMembers, Expenses, ExpenseSplits, ExpensePayers, Settlements])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connect());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tours, tours.startDate);
        await m.addColumn(tours, tours.endDate);
      }
      if (from < 3) {
        await m.addColumn(tours, tours.inviteCode);
      }
      if (from < 4) {
        await m.addColumn(users, users.email);
        await m.addColumn(users, users.avatarUrl);
      }
      if (from < 5) {
        await m.addColumn(users, users.purpose);
      }
      if (from < 6) {
        await m.addColumn(users, users.isMe);
        await customStatement('UPDATE users SET is_me = 1 WHERE id IN (SELECT id FROM users LIMIT 1)');
      }
      if (from < 7) {
        await m.addColumn(tourMembers, tourMembers.leftAt);
      }
      if (from < 8) {
        await m.createTable(settlements);
      }
      if (from < 9) {
        await m.createTable(expensePayers);
      }
    },
  );

  // CRUD Operations Wrapper
  Future<void> createUser(User user) => into(users).insert(user, mode: InsertMode.insertOrReplace);
  Future<List<User>> getAllUsers() => select(users).get();
  Future<User?> getUserById(String id) => (select(users)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<User>> getTourUsers(String tourId) {
    final query = select(users).join([
      innerJoin(tourMembers, tourMembers.userId.equalsExp(users.id)),
    ])..where(tourMembers.tourId.equals(tourId));
    return query.map((row) => row.readTable(users)).get();
  }

  Future<List<ExpenseSplit>> getSplitsByTour(String tourId) {
    final query = select(expenseSplits).join([
      innerJoin(expenses, expenses.id.equalsExp(expenseSplits.expenseId)),
    ])..where(expenses.tourId.equals(tourId));
    return query.map((row) => row.readTable(expenseSplits)).get();
  }

  Future<List<ExpensePayer>> getPayersByTour(String tourId) {
    final query = select(expensePayers).join([
      innerJoin(expenses, expenses.id.equalsExp(expensePayers.expenseId)),
    ])..where(expenses.tourId.equals(tourId));
    return query.map((row) => row.readTable(expensePayers)).get();
  }

  Future<List<Settlement>> getSettlementsByTour(String tourId) {
    return (select(settlements)..where((t) => t.tourId.equals(tourId))).get();
  }
  
  Future<void> createTour(Tour tour) => into(tours).insert(tour, mode: InsertMode.insertOrReplace);
  
  // Expenses with Transaction
  Future<void> addExpenseWithDetails(Expense expense, List<ExpenseSplit> splits, List<ExpensePayer> payers) {
    return transaction(() async {
      await into(expenses).insert(expense, mode: InsertMode.insertOrReplace);
      for (final split in splits) {
        await into(expenseSplits).insert(split, mode: InsertMode.insertOrReplace);
      }
      for (final payer in payers) {
        await into(expensePayers).insert(payer, mode: InsertMode.insertOrReplace);
      }
    });
  }

  Future<void> updateExpenseWithDetails(Expense expense, List<ExpenseSplit> splits, List<ExpensePayer> payers) {
    return transaction(() async {
      await update(expenses).replace(expense);
      await (delete(expenseSplits)..where((t) => t.expenseId.equals(expense.id))).go();
      await (delete(expensePayers)..where((t) => t.expenseId.equals(expense.id))).go();
      for (final split in splits) {
        await into(expenseSplits).insert(split);
      }
      for (final payer in payers) {
        await into(expensePayers).insert(payer);
      }
    });
  }

  Future<void> deleteExpenseWithDetails(String expenseId) {
    return transaction(() async {
      await (delete(expenseSplits)..where((t) => t.expenseId.equals(expenseId))).go();
      await (delete(expensePayers)..where((t) => t.expenseId.equals(expenseId))).go();
      await (delete(expenses)..where((t) => t.id.equals(expenseId))).go();
    });
  }

  Future<void> createSettlement(Settlement settlement) => into(settlements).insert(settlement, mode: InsertMode.insertOrReplace);
  Future<void> deleteSettlement(String id) => (delete(settlements)..where((t) => t.id.equals(id))).go();

  Future<void> deleteTourWithDetails(String tourId) {
    return transaction(() async {
      // 1. Get all expenses for this tour
      final tourExpenses = await (select(expenses)..where((t) => t.tourId.equals(tourId))).get();
      final expenseIds = tourExpenses.map((e) => e.id).toList();

      // 2. Delete Splis and Payers for these expenses
      if (expenseIds.isNotEmpty) {
        await (delete(expenseSplits)..where((t) => t.expenseId.isIn(expenseIds))).go();
        await (delete(expensePayers)..where((t) => t.expenseId.isIn(expenseIds))).go();
      }

      // 3. Delete Settlements
      await (delete(settlements)..where((t) => t.tourId.equals(tourId))).go();

      // 4. Delete Expenses
      await (delete(expenses)..where((t) => t.tourId.equals(tourId))).go();

      // 5. Delete Members
      await (delete(tourMembers)..where((t) => t.tourId.equals(tourId))).go();

      // 6. Delete Tour
      await (delete(tours)..where((t) => t.id.equals(tourId))).go();
    });
  }

  // Sync Queries
  Future<List<User>> getUnsyncedUsers() => (select(users)..where((t) => t.isSynced.equals(false))).get();
  Future<List<Tour>> getUnsyncedTours() => (select(tours)..where((t) => t.isSynced.equals(false))).get();
  Future<List<Expense>> getUnsyncedExpenses() => (select(expenses)..where((t) => t.isSynced.equals(false))).get();
  Future<List<ExpenseSplit>> getUnsyncedSplits() => (select(expenseSplits)..where((t) => t.isSynced.equals(false))).get();
  Future<List<ExpensePayer>> getUnsyncedExpensePayers() => (select(expensePayers)..where((t) => t.isSynced.equals(false))).get();
  Future<List<Settlement>> getUnsyncedSettlements() => (select(settlements)..where((t) => t.isSynced.equals(false))).get();
  
  Future<void> markUserSynced(String id) => (update(users)..where((t) => t.id.equals(id))).write(UsersCompanion(isSynced: Value(true)));
  Future<void> markTourSynced(String id) => (update(tours)..where((t) => t.id.equals(id))).write(ToursCompanion(isSynced: Value(true)));
  Future<void> markExpenseSynced(String id) => (update(expenses)..where((t) => t.id.equals(id))).write(ExpensesCompanion(isSynced: Value(true)));
  Future<void> markSplitSynced(String id) => (update(expenseSplits)..where((t) => t.id.equals(id))).write(ExpenseSplitsCompanion(isSynced: Value(true)));
  Future<void> markExpensePayerSynced(String id) => (update(expensePayers)..where((t) => t.id.equals(id))).write(ExpensePayersCompanion(isSynced: Value(true)));
  Future<void> markSettlementSynced(String id) => (update(settlements)..where((t) => t.id.equals(id))).write(SettlementsCompanion(isSynced: Value(true)));
  
  Future<void> markMemberAsLeft(String tourId, String userId) {
    return (update(tourMembers)
      ..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))
    ).write(TourMembersCompanion(leftAt: Value(DateTime.now())));
  }
}

