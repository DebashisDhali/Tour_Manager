import 'dart:math';
import '../../data/local/app_database.dart';

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

  UserBalanceDetails({
    required this.paid,
    required this.share,
    this.settled = 0.0,
    required this.net,
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

    final userMap = {for (var u in users) u.id: u};
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
  /// Supports: Tour (equal split), Mess (meal-based + fixed), Program (income-based)
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
    final paidMap = <String, double>{};
    final shareMap = <String, double>{};
    final settledMap = <String, double>{};

    // Initialize maps for all users
    for (var u in users) {
      paidMap[u.id] = 0.0;
      shareMap[u.id] = 0.0;
      settledMap[u.id] = 0.0;
    }

    // ===== STEP 1: CALCULATE PAID AMOUNTS =====

    // 1.1 Explicit expense payer records (highest priority)
    final expensesWithPayerRecords =
        expensePayers.map((p) => p.expenseId).toSet();

    for (var ep in expensePayers) {
      paidMap[ep.userId] = _roundTo2Decimals(
        (paidMap[ep.userId] ?? 0.0) + ep.amount,
      );
    }

    // 1.2 Fallback: expense.payerId for expenses without payer records
    for (var e in expenses) {
      if (!expensesWithPayerRecords.contains(e.id) && e.payerId != null) {
        paidMap[e.payerId!] = _roundTo2Decimals(
          (paidMap[e.payerId!] ?? 0.0) + e.amount,
        );
      }
    }

    // 1.3 Program incomes (collected funds)
    if (incomes != null) {
      for (var income in incomes) {
        paidMap[income.collectedBy] = _roundTo2Decimals(
          (paidMap[income.collectedBy] ?? 0.0) + income.amount,
        );
      }
    }

    // ===== STEP 2: CALCULATE SHARE OBLIGATIONS =====

    // Detect if this is a MESS tour with meal data
    bool hasMealData = purpose?.toLowerCase() == 'mess' &&
        mealCounts != null &&
        mealCounts.values.any((v) => v > 0);

    bool hasMealExpenses = purpose?.toLowerCase() == 'mess' &&
        expenses.any((e) => e.messCostType == 'meal');

    if (hasMealData || hasMealExpenses) {
      // ===== MESS MODE: Meal-based + Fixed Costs =====

      // Separate meal and fixed expenses
      final mealExpenses =
          expenses.where((e) => e.messCostType == 'meal').toList();
      final fixedExpenses =
          expenses.where((e) => e.messCostType == 'fixed').toList();

      final totalMealCost = mealExpenses.fold(0.0, (sum, e) => sum + e.amount);
      final totalFixedCost =
          fixedExpenses.fold(0.0, (sum, e) => sum + e.amount);

      // Identify participating members (those with meal count > 0)
      final participatingMembers = mealCounts?.entries
              .where((e) => e.value > 0)
              .map((e) => e.key)
              .toList() ??
          [];

      // ===== DISTRIBUTE FIXED COSTS (RENT, UTILITIES) =====
      // Fixed costs divided by ALL members (everyone occupies the space)
      // Even if not present, they're still sharing the rent
      if (users.isNotEmpty && totalFixedCost > 0) {
        final fixedPerMember = _roundTo2Decimals(totalFixedCost / users.length);

        // Calculate remainder to distribute (avoid rounding losses)
        final totalDistributed =
            _roundTo2Decimals(fixedPerMember * users.length);
        final fixedRemainder =
            _roundTo2Decimals(totalFixedCost - totalDistributed);

        for (int idx = 0; idx < users.length; idx++) {
          final userId = users[idx].id;
          // Add remainder to first member to prevent rounding loss
          final extraAmount = idx == 0 ? fixedRemainder : 0.0;
          shareMap[userId] = _roundTo2Decimals(fixedPerMember + extraAmount);
        }
      }

      // ===== DISTRIBUTE MEAL COSTS =====
      // Based on meal count per person
      final totalMeals =
          mealCounts?.values.fold(0.0, (sum, count) => sum + count) ?? 0.0;

      if (totalMeals > 0 && totalMealCost > 0) {
        final mealRate = _roundTo2Decimals(totalMealCost / totalMeals);

        // Calculate remainder for rounding error compensation
        final totalMealDistributed = _roundTo2Decimals(mealRate * totalMeals);
        final mealRemainder =
            _roundTo2Decimals(totalMealCost - totalMealDistributed);

        // Distribute meal costs proportional to meal count
        bool remainderAdded = false;
        for (var u in users) {
          final count = mealCounts?[u.id] ?? 0.0;
          if (count > 0) {
            final mealShare = _roundTo2Decimals(mealRate * count);
            // Add remainder to first participant
            final extraAmount = !remainderAdded && mealRemainder.abs() > 0.001
                ? mealRemainder
                : 0.0;
            if (extraAmount != 0) remainderAdded = true;

            shareMap[u.id] = _roundTo2Decimals(
              (shareMap[u.id] ?? 0.0) + mealShare + extraAmount,
            );
          }
        }
      }

      // ===== HANDLE NON-MESS SPLITS =====
      // Custom splits that aren't meal/fixed expenses
      final messManagedIds = expenses
          .where((e) => e.messCostType != null)
          .map((e) => e.id)
          .toSet();

      for (var split in splits) {
        if (!messManagedIds.contains(split.expenseId)) {
          shareMap[split.userId] = _roundTo2Decimals(
            (shareMap[split.userId] ?? 0.0) + split.amount,
          );
        }
      }
    } else {
      // ===== TOUR/PROGRAM MODE: Use Explicit Splits =====
      
      // Track total split amount per expense to find "orphaned" shares
      final Map<String, double> splitSumPerExpense = {};
      for (var split in splits) {
        splitSumPerExpense[split.expenseId] = (splitSumPerExpense[split.expenseId] ?? 0.0) + split.amount;
        
        // Only count the share if the user is in the active users list
        if (shareMap.containsKey(split.userId)) {
          shareMap[split.userId] = _roundTo2Decimals(
            (shareMap[split.userId] ?? 0.0) + split.amount,
          );
        }
      }

      // Check for missing amounts (orphaned splits or rounding remainders)
      for (var e in expenses) {
        final totalSplit = splitSumPerExpense[e.id] ?? 0.0;
        final missingAmount = _roundTo2Decimals(e.amount - totalSplit);
        
        // If money is missing from splits (e.g. someone was removed), 
        // the Payer absorbs that cost back by default.
        if (missingAmount.abs() > 0.01 && e.payerId != null && shareMap.containsKey(e.payerId!)) {
          shareMap[e.payerId!] = _roundTo2Decimals((shareMap[e.payerId!] ?? 0.0) + missingAmount);
        }
        
        // Also handle cases where a split exists for a removed user (orphaned share)
        final orphanedAmount = splits
            .where((s) => s.expenseId == e.id && !shareMap.containsKey(s.userId))
            .fold(0.0, (sum, s) => sum + s.amount);
            
        if (orphanedAmount > 0.01 && e.payerId != null && shareMap.containsKey(e.payerId!)) {
           shareMap[e.payerId!] = _roundTo2Decimals((shareMap[e.payerId!] ?? 0.0) + orphanedAmount);
        }
      }
    }

    // ===== STEP 3: ACCOUNT FOR PREVIOUS SETTLEMENTS =====
    // Adjust balances based on already-completed settlements
    for (var settlement in previousSettlements) {
      // fromId paid out (reduces their debt)
      settledMap[settlement.fromId] = _roundTo2Decimals(
        (settledMap[settlement.fromId] ?? 0.0) + settlement.amount,
      );
      // toId received (reduces their credit due)
      settledMap[settlement.toId] = _roundTo2Decimals(
        (settledMap[settlement.toId] ?? 0.0) - settlement.amount,
      );
    }

    // ===== STEP 4: CALCULATE FINAL NET BALANCE =====
    // net = paid - share + settled
    // positive: user is owed money | negative: user owes money

    final results = <String, UserBalanceDetails>{};
    for (var u in users) {
      final paid = _roundTo2Decimals(paidMap[u.id] ?? 0.0);
      final share = _roundTo2Decimals(shareMap[u.id] ?? 0.0);
      final settled = _roundTo2Decimals(settledMap[u.id] ?? 0.0);
      final net = _roundTo2Decimals(paid - share + settled);

      results[u.id] = UserBalanceDetails(
        paid: paid,
        share: share,
        settled: settled,
        net: net,
      );
    }

    return results;
  }
}

/// Internal helper for settlement optimization
class _BalanceItem {
  final String userId;
  double amount;

  _BalanceItem(this.userId, this.amount);
}
