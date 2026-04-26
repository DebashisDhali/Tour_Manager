import 'dart:math';
import 'package:drift/drift.dart';
import '../../data/local/app_database.dart';
import 'calculators/base_calculator.dart';
import 'calculators/tour_calculator.dart';
import 'calculators/mess_calculator.dart';
import 'calculators/event_calculator.dart';
import 'calculators/project_calculator.dart';
import 'calculators/party_calculator.dart';

class SettlementInstruction {
  final String payerId;
  final String payerName;
  final String receiverId;
  final String receiverName;
  final double amount;

  SettlementInstruction({
    required this.payerId,
    required this.payerName,
    required this.receiverId,
    required this.receiverName,
    required this.amount,
  });
}

class UserBalanceDetails {
  final double paid;
  final double share;
  final double settled; // Previous settlements (money received - money paid)
  final double net;
  final List<BalanceItem> items;

  UserBalanceDetails({
    required this.paid,
    required this.share,
    this.settled = 0.0,
    required this.net,
    this.items = const [],
  });
}

class BalanceItem {
  final String title;
  final double amount;
  final String type; // 'paid', 'share', 'settled'
  final bool isCredit;

  BalanceItem({
    required this.title,
    required this.amount,
    required this.type,
    required this.isCredit,
  });
}

/// High-precision settlement calculator with optimized transaction minimization
class SettlementCalculator {
  /// Rounds to 2 decimal places with proper floating point handling
  /// Uses rounding to nearest, with 0.5 going away from zero
  static double _roundTo2Decimals(double value) {
    return (value * 100).round() / 100;
  }

  /// Calculates the optimized settlement plan with minimum transactions
  /// Uses greedy two-pointer algorithm to minimize number of settlements
  List<SettlementInstruction> calculate(
    List<Expense> expenses,
    List<ExpenseSplit> splits,
    List<ExpensePayer> expensePayers,
    List<User> users,
    List<Settlement> previousSettlements, {
    String? purpose,
    Map<String, double>? mealCounts,
    List<ProgramIncome>? incomes,
  }) {
    // 1. Calculate net balances for each user
    final balanceMap = getFullBalances(
      expenses: expenses,
      splits: splits,
      expensePayers: expensePayers,
      users: users,
      previousSettlements: previousSettlements,
      purpose: purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );

    // 2. Separate into debtors (negative balance) and creditors (positive balance)
    final debtors = <_BalanceItem>[];
    final creditors = <_BalanceItem>[];

    balanceMap.forEach((userId, details) {
      final amount = _roundTo2Decimals(details.net);

      // Use 0.005 threshold to filter out micro-transactions and rounding errors
      if (amount < -0.005) {
        debtors.add(_BalanceItem(userId, amount));
      } else if (amount > 0.005) {
        creditors.add(_BalanceItem(userId, amount));
      }
    });

    // 3. Sort for greedy algorithm optimization
    // Debtors ascending: people who owe most go first
    debtors.sort((a, b) => a.amount.compareTo(b.amount));
    // Creditors descending: people owed most go first
    creditors.sort((a, b) => b.amount.compareTo(a.amount));

    // Normalize userMap keys for reliable lookups
    final userMap = {for (var u in users) u.id.toLowerCase(): u};
    final settlements = <SettlementInstruction>[];

    // 4. Two-pointer greedy algorithm for optimal settlements
    int i = 0; // Debtor pointer
    int j = 0; // Creditor pointer

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];

      // Calculate settlement amount
      double amount = min(debtor.amount.abs(), creditor.amount);
      amount = _roundTo2Decimals(amount);

      // Skip if amount is negligible (avoid micro-transactions)
      if (amount < 0.01) {
        if (debtor.amount.abs() < 0.005) i++;
        if (creditor.amount.abs() < 0.005) j++;
        continue;
      }

      final debtorUser = userMap[debtor.userId];
      final creditorUser = userMap[creditor.userId];

      if (debtorUser == null || creditorUser == null) {
        i++;
        j++;
        continue;
      }

      // Record settlement instruction
      settlements.add(SettlementInstruction(
        payerId: debtorUser.id,
        payerName: debtorUser.name,
        receiverId: creditorUser.id,
        receiverName: creditorUser.name,
        amount: amount,
      ));

      // Update balances
      debtor.amount = _roundTo2Decimals(debtor.amount + amount);
      creditor.amount = _roundTo2Decimals(creditor.amount - amount);

      // Move to next person if settled
      if (debtor.amount.abs() < 0.005) i++;
      if (creditor.amount.abs() < 0.005) j++;
    }

    return settlements;
  }

  /// Calculates complete balance details for all users
  /// Accounts for: paid amounts, shares (obligations), previous settlements
  /// Delegates to specialized calculators based on purpose for 100% accuracy
  Map<String, UserBalanceDetails> getFullBalances({
    required List<Expense> expenses,
    required List<ExpenseSplit> splits,
    required List<ExpensePayer> expensePayers,
    required List<User> users,
    required List<Settlement> previousSettlements,
    String? purpose,
    Map<String, double>? mealCounts,
    List<ProgramIncome>? incomes,
  }) {
    // 0. Normalize and Deduplicate all inputs at the entry point (Case-Insensitive)
    final Map<String, User> uniqueUsers = {};
    for (var u in users) {
      final normalizedId = u.id.toLowerCase();
      if (!uniqueUsers.containsKey(normalizedId)) {
        uniqueUsers[normalizedId] = u.copyWith(id: normalizedId);
      }
    }
    final deduplicatedUsers = uniqueUsers.values.toList();

    final Map<String, Expense> uniqueExpenses = {};
    for (var e in expenses) {
      if (e.isDeleted) continue;
      final normalizedId = e.id.toLowerCase();
      if (!uniqueExpenses.containsKey(normalizedId)) {
        uniqueExpenses[normalizedId] = e.copyWith(
          id: normalizedId,
          payerId: Value(e.payerId?.toLowerCase()),
          tourId: e.tourId.toLowerCase(),
        );
      }
    }
    final deduplicatedExpenses = uniqueExpenses.values.toList();

    final Map<String, ExpenseSplit> uniqueSplits = {};
    final Set<String> seenUserSplits = {}; // composite key: expenseId_userId

    for (var s in splits) {
      if (s.isDeleted) continue;
      final normalizedId = s.id.toLowerCase();
      final normalizedExpId = s.expenseId.toLowerCase();
      final normalizedUserId = s.userId.toLowerCase();
      
      // CRITICAL INTEGRITY CHECK: 
      // 1. Must belong to an active expense in THIS tour
      // 2. Must belong to an active user in THIS tour
      if (!uniqueExpenses.containsKey(normalizedExpId)) {
        print("DEBUG: Purging orphaned split for unknown expense $normalizedExpId");
        continue;
      }
      if (!uniqueUsers.containsKey(normalizedUserId)) {
        print("DEBUG: Purging split for user $normalizedUserId who is not in this project");
        continue;
      }

      // 3. Deduplication: One split per user per expense
      final contentKey = "${normalizedExpId}_$normalizedUserId";
      if (seenUserSplits.contains(contentKey)) continue;

      if (!uniqueSplits.containsKey(normalizedId)) {
        uniqueSplits[normalizedId] = s.copyWith(
          id: normalizedId,
          expenseId: normalizedExpId,
          userId: normalizedUserId,
        );
        seenUserSplits.add(contentKey);
      }
    }
    final deduplicatedSplits = uniqueSplits.values.toList();

    final Map<String, ExpensePayer> uniquePayers = {};
    for (var p in expensePayers) {
      if (p.isDeleted) continue;
      final normalizedId = p.id.toLowerCase();
      final normalizedExpId = p.expenseId.toLowerCase();
      
      // Safety: Only include payers for expenses that are active in this calculation
      if (!uniqueExpenses.containsKey(normalizedExpId)) continue;

      if (!uniquePayers.containsKey(normalizedId)) {
        uniquePayers[normalizedId] = p.copyWith(
          id: normalizedId,
          expenseId: normalizedExpId,
          userId: p.userId.toLowerCase(),
        );
      }
    }
    final deduplicatedPayers = uniquePayers.values.toList();

    final Map<String, Settlement> uniqueSettlements = {};
    for (var s in previousSettlements) {
      if (s.isDeleted) continue;
      if (!uniqueSettlements.containsKey(s.id)) {
        uniqueSettlements[s.id] = s.copyWith(
          fromId: s.fromId.toLowerCase(),
          toId: s.toId.toLowerCase(),
        );
      }
    }
    final deduplicatedSettlements = uniqueSettlements.values.toList();
    
    final normalizedMealCounts = mealCounts?.map((k, v) => MapEntry(k.toLowerCase(), v));
    final normalizedIncomes = incomes?.where((i) => !i.isDeleted).map((i) => i.copyWith(collectedBy: i.collectedBy.toLowerCase())).toList();

    // 1. Select the appropriate calculator based on purpose
    BaseSettlementCalculator calculator;
    
    final normalizedPurpose = purpose?.trim().toLowerCase();
    switch (normalizedPurpose) {
      case 'mess':
        calculator = MessSettlementCalculator();
        break;
      case 'event':
        calculator = EventSettlementCalculator();
        break;
      case 'project':
      case 'office':
        calculator = ProjectSettlementCalculator();
        break;
      case 'party':
        calculator = PartySettlementCalculator();
        break;
      case 'tour':
      default:
        calculator = TourSettlementCalculator();
        break;
    }

    // 2. Execute calculation with clean, normalized data
    return calculator.calculateBalances(
      expenses: deduplicatedExpenses,
      splits: deduplicatedSplits,
      expensePayers: deduplicatedPayers,
      users: deduplicatedUsers,
      previousSettlements: deduplicatedSettlements,
      mealCounts: normalizedMealCounts,
      incomes: normalizedIncomes,
    );
  }
}

/// Internal helper for settlement optimization
class _BalanceItem {
  final String userId;
  double amount;

  _BalanceItem(this.userId, this.amount);
}
