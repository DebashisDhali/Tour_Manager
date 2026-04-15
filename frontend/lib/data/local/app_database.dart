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
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

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
  TextColumn get purpose => text().withDefault(const Constant('tour'))(); // 'tour', 'event', 'project', etc.
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TourMembers extends Table {
  TextColumn get tourId => text().references(Tours, #id)();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get mealCount => real().withDefault(const Constant(0.0))(); // For Mess sessions
  DateTimeColumn get leftAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get role => text().withDefault(const Constant('viewer'))(); // 'admin', 'editor', 'viewer'
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  
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
  TextColumn get messCostType => text().nullable()(); // 'fixed' or 'meal' (bazar)
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
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
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ExpensePayers extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text().references(Expenses, #id)();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get amount => real()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

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
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgramIncomes extends Table {
  TextColumn get id => text()();
  TextColumn get tourId => text().references(Tours, #id)();
  RealColumn get amount => real()();
  TextColumn get source => text()(); // 'Department', 'Ticket', 'Senior', etc.
  TextColumn get description => text().nullable()();
  TextColumn get collectedBy => text().references(Users, #id)();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class MealRecords extends Table {
  TextColumn get id => text()();
  TextColumn get tourId => text().references(Tours, #id)();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get date => dateTime()();
  RealColumn get count => real()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class JoinRequests extends Table {
  TextColumn get id => text()();
  TextColumn get tourId => text().references(Tours, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get userName => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, approved, rejected
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Users, Tours, TourMembers, Expenses, ExpenseSplits, ExpensePayers, Settlements, ProgramIncomes, MealRecords, SyncMetadata, JoinRequests])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connect());

  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      
      final now = DateTime.now().millisecondsSinceEpoch;
      // Patch potential null values in critical columns Individually
      Future<void> safePatch(String sql) async {
        try {
          await customStatement(sql);
        } catch (_) {}
      }

      await safePatch('UPDATE users SET created_at = $now WHERE created_at IS NULL');
      await safePatch('UPDATE users SET updated_at = $now WHERE updated_at IS NULL');
      await safePatch('UPDATE tours SET updated_at = $now WHERE updated_at IS NULL');
      await safePatch('UPDATE tours SET purpose = "tour" WHERE purpose IS NULL');
      await safePatch('UPDATE users SET purpose = "tour" WHERE purpose IS NULL');
      await safePatch('UPDATE users SET is_me = 0 WHERE is_me IS NULL');
      await safePatch('UPDATE users SET name = "User" WHERE name IS NULL'); // Exhaustive
      await safePatch('UPDATE tours SET created_by = "" WHERE created_by IS NULL'); // Exhaustive
      await safePatch('UPDATE tours SET name = "Tour" WHERE name IS NULL'); // Exhaustive
      await safePatch('UPDATE tour_members SET status = "active" WHERE status IS NULL');
      await safePatch('UPDATE tour_members SET role = "viewer" WHERE role IS NULL');
      await safePatch('UPDATE tour_members SET meal_count = 0.0 WHERE meal_count IS NULL');
      await safePatch('UPDATE expenses SET created_at = $now WHERE created_at IS NULL');
      await safePatch('UPDATE expenses SET amount = 0.0 WHERE amount IS NULL'); // Exhaustive
      await safePatch('UPDATE expenses SET title = "Expense" WHERE title IS NULL'); // Exhaustive
      await safePatch('UPDATE expenses SET category = "Other" WHERE category IS NULL'); // Exhaustive
      await safePatch('UPDATE expense_splits SET amount = 0.0 WHERE amount IS NULL'); // Exhaustive
      await safePatch('UPDATE expense_payers SET amount = 0.0 WHERE amount IS NULL'); // Exhaustive
      await safePatch('UPDATE settlements SET date = $now WHERE date IS NULL');
      await safePatch('UPDATE settlements SET amount = 0.0 WHERE amount IS NULL'); // Exhaustive
      await safePatch('UPDATE program_incomes SET date = $now WHERE date IS NULL');
      await safePatch('UPDATE program_incomes SET amount = 0.0 WHERE amount IS NULL'); // Exhaustive
      await safePatch('UPDATE join_requests SET status = "pending" WHERE status IS NULL');

      final tablesWithIsDeleted = [
        'users', 'tours', 'tour_members', 'expenses', 'expense_splits', 
        'expense_payers', 'settlements', 'program_incomes', 'meal_records', 'join_requests'
      ];
      for (var table in tablesWithIsDeleted) {
        await safePatch('UPDATE $table SET is_deleted = 0 WHERE is_deleted IS NULL');
        await safePatch('UPDATE $table SET is_synced = 0 WHERE is_synced IS NULL');
      }
    },
    onUpgrade: (m, from, to) async {
      Future<void> addColumnSafe(TableInfo table, GeneratedColumn column) async {
        try {
          await m.addColumn(table, column);
        } catch (e) {
          if (!e.toString().contains('duplicate column name')) rethrow;
        }
      }

      Future<void> runSqlSafe(String sql) async {
        try {
          await customStatement(sql);
        } catch (e) {
          if (!e.toString().contains('duplicate column name')) rethrow;
        }
      }

      if (from < 2) {
        await addColumnSafe(tours, tours.startDate);
        await addColumnSafe(tours, tours.endDate);
      }
      if (from < 3) {
        await addColumnSafe(tours, tours.inviteCode);
      }
      if (from < 4) {
        await addColumnSafe(users, users.email);
        await addColumnSafe(users, users.avatarUrl);
      }
      if (from < 5) {
        await addColumnSafe(users, users.purpose);
      }
      if (from < 6) {
        await addColumnSafe(users, users.isMe);
        await customStatement('UPDATE users SET is_me = 1 WHERE id IN (SELECT id FROM users LIMIT 1)');
      }
      if (from < 7) {
        await addColumnSafe(tourMembers, tourMembers.leftAt);
      }
      if (from < 8) {
        await m.createTable(settlements);
      }
      if (from < 9) {
        await m.createTable(expensePayers);
      }
      if (from < 10) {
        await m.createTable(programIncomes);
      }
      if (from < 11) {
        await addColumnSafe(tours, tours.purpose);
      }
      if (from < 12) {
        await addColumnSafe(tourMembers, tourMembers.mealCount);
        await addColumnSafe(expenses, expenses.messCostType);
      }
      if (from < 13) {
        await m.createTable(mealRecords);
      }
      if (from < 14) {
        await addColumnSafe(tourMembers, tourMembers.status);
      }
      if (from < 15) {
        await addColumnSafe(users, users.updatedAt);
        await addColumnSafe(tours, tours.updatedAt);
      }
      if (from < 16) {
        await m.createTable(syncMetadata);
      }
      if (from < 17) {
        await addColumnSafe(tourMembers, tourMembers.role);
      }
      if (from < 18) {
        await m.createTable(joinRequests);
      }
      if (from < 19) {
        await addColumnSafe(tours, tours.isDeleted);
        await addColumnSafe(expenses, expenses.isDeleted);
        await addColumnSafe(expenseSplits, expenseSplits.isDeleted);
        await addColumnSafe(expensePayers, expensePayers.isDeleted);
        await addColumnSafe(settlements, settlements.isDeleted);
        await addColumnSafe(programIncomes, programIncomes.isDeleted);
      }
      if (from < 20) {
        await runSqlSafe('ALTER TABLE users ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
        await runSqlSafe('ALTER TABLE tour_members ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
        await runSqlSafe('ALTER TABLE meal_records ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
        await runSqlSafe('ALTER TABLE users ADD COLUMN created_at INTEGER');
        await runSqlSafe('ALTER TABLE users ADD COLUMN updated_at INTEGER');
        
        final now = DateTime.now().millisecondsSinceEpoch;
        await customStatement('UPDATE users SET created_at = $now WHERE created_at IS NULL');
        await customStatement('UPDATE users SET updated_at = $now WHERE updated_at IS NULL');
        await customStatement('UPDATE tours SET updated_at = $now WHERE updated_at IS NULL');
        await customStatement('UPDATE tours SET is_deleted = 0 WHERE is_deleted IS NULL');
        await customStatement('UPDATE expenses SET is_deleted = 0 WHERE is_deleted IS NULL');
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

  Future<List<ProgramIncome>> getProgramIncomesByTour(String tourId) {
    return (select(programIncomes)..where((t) => t.tourId.equals(tourId))).get();
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
      await into(expenses).insert(expense, mode: InsertMode.insertOrReplace);
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
      await (update(expenses)..where((t) => t.id.equals(expenseId))).write(const ExpensesCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(expenseSplits)..where((t) => t.expenseId.equals(expenseId))).write(const ExpenseSplitsCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(expensePayers)..where((t) => t.expenseId.equals(expenseId))).write(const ExpensePayersCompanion(isDeleted: Value(true), isSynced: Value(false)));
    });
  }

  Future<void> hardDeleteExpenseWithDetails(String expenseId) {
    return transaction(() async {
      await (delete(expenseSplits)..where((t) => t.expenseId.equals(expenseId))).go();
      await (delete(expensePayers)..where((t) => t.expenseId.equals(expenseId))).go();
      await (delete(expenses)..where((t) => t.id.equals(expenseId))).go();
    });
  }

  Future<void> createSettlement(Settlement settlement) => into(settlements).insert(settlement, mode: InsertMode.insertOrReplace);
  Future<void> deleteSettlement(String id) => (update(settlements)..where((t) => t.id.equals(id))).write(const SettlementsCompanion(isDeleted: Value(true), isSynced: Value(false)));
  Future<void> hardDeleteSettlement(String id) => (delete(settlements)..where((t) => t.id.equals(id))).go();

  Future<void> createProgramIncome(ProgramIncome income) => into(programIncomes).insert(income, mode: InsertMode.insertOrReplace);
  Future<void> deleteProgramIncome(String id) => (update(programIncomes)..where((t) => t.id.equals(id))).write(const ProgramIncomesCompanion(isDeleted: Value(true), isSynced: Value(false)));
  Future<void> hardDeleteProgramIncome(String id) => (delete(programIncomes)..where((t) => t.id.equals(id))).go();

  Future<void> deleteTourWithDetails(String tourId) {
    return transaction(() async {
      await (update(tours)..where((t) => t.id.equals(tourId))).write(const ToursCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(expenses)..where((t) => t.tourId.equals(tourId))).write(const ExpensesCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(expenseSplits)..where((s) => s.expenseId.isInQuery(
        selectOnly(expenses)..addColumns([expenses.id])..where(expenses.tourId.equals(tourId))
      ))).write(const ExpenseSplitsCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(expensePayers)..where((p) => p.expenseId.isInQuery(
        selectOnly(expenses)..addColumns([expenses.id])..where(expenses.tourId.equals(tourId))
      ))).write(const ExpensePayersCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(settlements)..where((t) => t.tourId.equals(tourId))).write(const SettlementsCompanion(isDeleted: Value(true), isSynced: Value(false)));
      await (update(programIncomes)..where((t) => t.tourId.equals(tourId))).write(const ProgramIncomesCompanion(isDeleted: Value(true), isSynced: Value(false)));
    });
  }

  Future<void> hardDeleteTourWithDetails(String tourId) {
    return transaction(() async {
      // 1. Get all expenses for this tour
      final tourExpenses = await (select(expenses)..where((t) => t.tourId.equals(tourId))).get();
      final expenseIds = tourExpenses.map((e) => e.id).toList();

      // 2. Delete Splis and Payers for these expenses
      if (expenseIds.isNotEmpty) {
        await (delete(expenseSplits)..where((t) => t.expenseId.isIn(expenseIds))).go();
        await (delete(expensePayers)..where((t) => t.expenseId.isIn(expenseIds))).go();
      }

      // 3. Delete Settlements & Incomes & Other Dependencies
      await (delete(settlements)..where((t) => t.tourId.equals(tourId))).go();
      await (delete(programIncomes)..where((t) => t.tourId.equals(tourId))).go();
      await (delete(joinRequests)..where((t) => t.tourId.equals(tourId))).go();
      await (delete(mealRecords)..where((t) => t.tourId.equals(tourId))).go();

      // 4. Delete Expenses
      await (delete(expenses)..where((t) => t.tourId.equals(tourId))).go();

      // 5. Delete Members
      await (delete(tourMembers)..where((t) => t.tourId.equals(tourId))).go();

      // 6. Delete Tour
      await (delete(tours)..where((t) => t.id.equals(tourId))).go();
    });
  }

  // Sync Queries (Unsynced includes those modified OR marked for deletion)
  Future<List<User>> getUnsyncedUsers() => (select(users)..where((t) => t.isSynced.equals(false))).get();
  Future<List<Tour>> getUnsyncedTours() => (select(tours)..where((t) => t.isSynced.equals(false))).get();
  Future<List<Expense>> getUnsyncedExpenses() => (select(expenses)..where((t) => t.isSynced.equals(false))).get();
  Future<List<ExpenseSplit>> getUnsyncedSplits() => (select(expenseSplits)..where((t) => t.isSynced.equals(false))).get();
  Future<List<ExpensePayer>> getUnsyncedExpensePayers() => (select(expensePayers)..where((t) => t.isSynced.equals(false))).get();
  Future<List<TourMember>> getUnsyncedTourMembers() => (select(tourMembers)..where((t) => t.isSynced.equals(false))).get();
  Future<List<Settlement>> getUnsyncedSettlements() => (select(settlements)..where((t) => t.isSynced.equals(false))).get();
  Future<List<ProgramIncome>> getUnsyncedProgramIncomes() => (select(programIncomes)..where((t) => t.isSynced.equals(false))).get();
  
  // Normal Fetchers (Filter out deleted)
  Stream<List<Tour>> watchAllTours() => (select(tours)..where((t) => t.isDeleted.equals(false))).watch();
  Future<List<Tour>> getAllTours() => (select(tours)..where((t) => t.isDeleted.equals(false))).get();
  Future<List<Expense>> getExpensesByTour(String tourId) => (select(expenses)..where((t) => t.tourId.equals(tourId) & t.isDeleted.equals(false))).get();
  
  Future<void> markUserSynced(String id) => (update(users)..where((t) => t.id.equals(id))).write(UsersCompanion(isSynced: Value(true)));
  Future<void> markTourSynced(String id) => (update(tours)..where((t) => t.id.equals(id))).write(ToursCompanion(isSynced: Value(true)));
  Future<void> markTourMemberSynced(String tourId, String userId) => (update(tourMembers)..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))).write(TourMembersCompanion(isSynced: const Value(true)));
  Future<void> markExpenseSynced(String id) => (update(expenses)..where((t) => t.id.equals(id))).write(ExpensesCompanion(isSynced: Value(true)));
  Future<void> markSplitSynced(String id) => (update(expenseSplits)..where((t) => t.id.equals(id))).write(ExpenseSplitsCompanion(isSynced: Value(true)));
  Future<void> markExpensePayerSynced(String id) => (update(expensePayers)..where((t) => t.id.equals(id))).write(ExpensePayersCompanion(isSynced: Value(true)));
  Future<void> markSettlementSynced(String id) => (update(settlements)..where((t) => t.id.equals(id))).write(SettlementsCompanion(isSynced: Value(true)));
  Future<void> markProgramIncomeSynced(String id) => (update(programIncomes)..where((t) => t.id.equals(id))).write(ProgramIncomesCompanion(isSynced: Value(true)));
  Future<void> markJoinRequestSynced(String id) => (update(joinRequests)..where((t) => t.id.equals(id))).write(JoinRequestsCompanion(isSynced: const Value(true)));
  
  Future<List<JoinRequest>> getUnsyncedJoinRequests() => (select(joinRequests)..where((t) => t.isSynced.equals(false))).get();
  Future<List<JoinRequest>> getJoinRequestsByTour(String tourId) => (select(joinRequests)..where((t) => t.tourId.equals(tourId))).get();

  Future<void> markMemberAsLeft(String tourId, String userId) {
    return (update(tourMembers)
      ..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))
    ).write(TourMembersCompanion(
      status: const Value('removed'),
      leftAt: Value(DateTime.now()),
      isSynced: const Value(false),
    ));
  }

  Future<void> reactivateMember(String tourId, String userId) {
    return (update(tourMembers)
      ..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))
    ).write(const TourMembersCompanion(
      status: Value('active'),
      leftAt: Value(null),
      isSynced: Value(false),
    ));
  }

  Future<void> updateMealCount(String tourId, String userId, double count) {
    return (update(tourMembers)
      ..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))
    ).write(TourMembersCompanion(mealCount: Value(count), isSynced: const Value(false)));
  }

  Future<void> updateMemberRole(String tourId, String userId, String role) {
    return (update(tourMembers)
      ..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))
    ).write(TourMembersCompanion(role: Value(role), isSynced: const Value(false)));
  }

  // Meal Records
  Future<void> upsertMealRecord(MealRecord record) async {
    await into(mealRecords).insertOnConflictUpdate(record);
    await _recalculateTotalMeals(record.tourId, record.userId);
  }

  Future<void> deleteMealRecord(String id, String tourId, String userId) async {
    await (delete(mealRecords)..where((t) => t.id.equals(id))).go();
    await _recalculateTotalMeals(tourId, userId);
  }

  Future<void> _recalculateTotalMeals(String tourId, String userId) async {
    final records = await (select(mealRecords)..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId))).get();
    final total = records.fold(0.0, (sum, r) => sum + r.count);
    await (update(tourMembers)..where((t) => t.tourId.equals(tourId) & t.userId.equals(userId)))
        .write(TourMembersCompanion(mealCount: Value(total), isSynced: const Value(false)));
  }

  Stream<List<MealRecord>> watchMealRecords(String tourId) => 
      (select(mealRecords)..where((t) => t.tourId.equals(tourId))..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  Future<List<MealRecord>> getMealRecordsForDate(String tourId, DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (select(mealRecords)..where((t) => t.tourId.equals(tourId) & t.date.isBetweenValues(start, end))).get();
  }

  Future<String?> getSyncMetadata(String key) async {
    final row = await (select(syncMetadata)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSyncMetadata(String key, String value) async {
    await into(syncMetadata).insertOnConflictUpdate(SyncMetadataCompanion(
      key: Value(key),
      value: Value(value),
    ));
  }

  Future<void> clearAllData() {
    return transaction(() async {
      await customStatement('PRAGMA foreign_keys = OFF');
      try {
        for (final table in allTables) {
          await delete(table).go();
        }
      } finally {
        await customStatement('PRAGMA foreign_keys = ON');
      }
    });
  }
}

