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

    // Initialize maps for all users with normalized IDs (lowercase)
    for (var u in users) {
      final nid = u.id.toLowerCase();
      paidMap[nid] = 0.0;
      shareMap[nid] = 0.0;
      settledMap[nid] = 0.0;
    }

    // ===== STEP 1: CALCULATE PAID AMOUNTS =====

    // 1.1 Explicit expense payer records (highest priority)
    final expensesWithPayerRecords =
        expensePayers.map((p) => p.expenseId).toSet();
    
    // Normalize user IDs for all lookups in maps
    for (var ep in expensePayers) {
      final nid = ep.userId.toLowerCase();
      paidMap[nid] = _roundTo2Decimals(
        (paidMap[nid] ?? 0.0) + ep.amount,
      );
    }

    // 1.2 Fallback: expense.payerId for expenses without payer records
    for (var e in expenses) {
      if (!expensesWithPayerRecords.contains(e.id) && e.payerId != null) {
        final nid = e.payerId!.toLowerCase();
        paidMap[nid] = _roundTo2Decimals(
          (paidMap[nid] ?? 0.0) + e.amount,
        );
      }
    }

    // 1.3 Program incomes (collected funds)
    if (incomes != null) {
      for (var income in incomes) {
        final nid = income.collectedBy.toLowerCase();
        paidMap[nid] = _roundTo2Decimals(
          (paidMap[nid] ?? 0.0) + income.amount,
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

      // ===== DISTRIBUTE FIXED COSTS (RENT, UTILITIES) =====
      // Fixed costs divided by ALL members (everyone occupies the space)
      // Even if not present, they're still sharing the rent
      
      // Fallback: any expense in mess mode that is NOT marked as 'meal' 
      // and has no explicit splits should be treated as shared fixed cost.
      final expensesWithSplits = splits.map((s) => s.expenseId).toSet();
      
      final actualFixedExpenses = expenses.where((e) => 
        e.messCostType == 'fixed' || 
        (e.messCostType == null && !expensesWithSplits.contains(e.id))
      ).toList();
      
      final totalFixedCost = actualFixedExpenses.fold(0.0, (sum, e) => sum + e.amount);

      if (users.isNotEmpty && totalFixedCost > 0) {
        final fixedPerMember = _roundTo2Decimals(totalFixedCost / users.length);

        // Calculate remainder to distribute (avoid rounding losses)
        final totalDistributed =
            _roundTo2Decimals(fixedPerMember * users.length);
        final fixedRemainder =
            _roundTo2Decimals(totalFixedCost - totalDistributed);

        for (int idx = 0; idx < users.length; idx++) {
          final nid = users[idx].id.toLowerCase();
          // Add remainder to first member to prevent rounding loss
          final extraAmount = idx == 0 ? fixedRemainder : 0.0;
          shareMap[nid] = _roundTo2Decimals(fixedPerMember + extraAmount);
        }
      }

      // ===== DISTRIBUTE MEAL COSTS =====
      // Based on meal count per person
      final mealExpenses =
          expenses.where((e) => e.messCostType == 'meal').toList();
      final totalMealCost = mealExpenses.fold(0.0, (sum, e) => sum + e.amount);
      
      final totalMeals =
          mealCounts?.values.fold(0.0, (sum, count) => sum + count) ?? 0.0;

      if (totalMeals > 0 && totalMealCost > 0) {
        final mealRate = totalMealCost / totalMeals; // Keep precision for now

        // Distribute meal costs proportional to meal count
        double totalDistributedMeal = 0.0;
        final participatingNids = <String>[];
        
        for (var u in users) {
          final nid = u.id.toLowerCase();
          final count = mealCounts?[u.id] ?? mealCounts?[nid] ?? 0.0;
          if (count > 0) {
            participatingNids.add(nid);
            final mealShare = _roundTo2Decimals(mealRate * count);
            totalDistributedMeal += mealShare;
            shareMap[nid] = _roundTo2Decimals((shareMap[nid] ?? 0.0) + mealShare);
          }
        }
        
        // Rounding compensation for meals
        final mealRemainder = _roundTo2Decimals(totalMealCost - totalDistributedMeal);
        if (mealRemainder.abs() > 0.001 && participatingNids.isNotEmpty) {
          final pNid = participatingNids.first;
          shareMap[pNid] = _roundTo2Decimals((shareMap[pNid] ?? 0.0) + mealRemainder);
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
          final nid = split.userId.toLowerCase();
          if (shareMap.containsKey(nid)) {
             shareMap[nid] = _roundTo2Decimals(
               (shareMap[nid] ?? 0.0) + split.amount,
             );
          }
        }
      }
    } else {
      // ===== TOUR/PROGRAM MODE: Use Explicit Splits =====
      
      // Track total split amount per expense to find "orphaned" shares
      final Map<String, double> splitSumPerExpense = {};
      
      // Deduplicate splits per user per expense to avoid double-counting sync errors
      final Map<String, Map<String, double>> dedupedSplits = {};
      for (var split in splits) {
        final eid = split.expenseId;
        final uid = split.userId.toLowerCase();
        
        if (!dedupedSplits.containsKey(eid)) {
          dedupedSplits[eid] = {};
        }
        
        // If we have duplicates, we'll take the one that actually matches the intended share 
        // Or just keep the latest (simple approach)
        dedupedSplits[eid]![uid] = split.amount;
      }

      // Now process the deduped splits
      for (var eid in dedupedSplits.keys) {
        final userSplits = dedupedSplits[eid]!;
        for (var uid in userSplits.keys) {
          final amount = userSplits[uid]!;
          splitSumPerExpense[eid] = (splitSumPerExpense[eid] ?? 0.0) + amount;
          
          if (shareMap.containsKey(uid)) {
            shareMap[uid] = _roundTo2Decimals(
              (shareMap[uid] ?? 0.0) + amount,
            );
          }
        }
      }

      // Check for missing amounts (orphaned splits or rounding remainders)
      for (var e in expenses) {
        final totalSplit = splitSumPerExpense[e.id] ?? 0.0;
        final missingAmount = _roundTo2Decimals(e.amount - totalSplit);
        
        final pNid = e.payerId?.toLowerCase();
        // If money is missing from splits (e.g. someone was removed), 
        // the Payer absorbs that cost back by default.
        if (missingAmount.abs() > 0.01 && pNid != null && shareMap.containsKey(pNid)) {
          shareMap[pNid] = _roundTo2Decimals((shareMap[pNid] ?? 0.0) + missingAmount);
        }
        
        // Also handle cases where a split exists for a removed user (orphaned share)
        final Map<String, double> userSplits = dedupedSplits[e.id] ?? {};
        double orphanedAmount = 0.0;
        
        for (var uid in userSplits.keys) {
          if (!shareMap.containsKey(uid.toLowerCase())) {
            orphanedAmount += userSplits[uid]!;
          }
        }
            
        // COMBINED RECOVERY: Missing amounts + Orphaned shares
        final totalRecovery = missingAmount + orphanedAmount;
        
        if (totalRecovery.abs() > 0.01) {
          // Redistribute the recovery amount among all active members in shareMap
          final activeMemberNids = shareMap.keys.toList();
          if (activeMemberNids.isNotEmpty) {
            final shareOfRecovery = _roundTo2Decimals(totalRecovery / activeMemberNids.length);
            
            for (int i = 0; i < activeMemberNids.length; i++) {
              final nid = activeMemberNids[i];
              // Add the share of recovery to each member
              double adjustedAmount = shareOfRecovery;
              
              // Handle rounding remainders by giving the last bit to the First member
              if (i == 0) {
                final totalRedistributed = shareOfRecovery * activeMemberNids.length;
                final remainder = _roundTo2Decimals(totalRecovery - totalRedistributed);
                adjustedAmount = _roundTo2Decimals(adjustedAmount + remainder);
              }
              
              shareMap[nid] = _roundTo2Decimals((shareMap[nid] ?? 0.0) + adjustedAmount);
            }
          } else if (pNid != null && shareMap.containsKey(pNid)) {
            // Fallback to payer if no active members (shouldn't happen)
            shareMap[pNid] = _roundTo2Decimals((shareMap[pNid] ?? 0.0) + totalRecovery);
          }
        }
      }
    }

    // ===== STEP 3: ACCOUNT FOR PREVIOUS SETTLEMENTS =====
    // Adjust balances based on already-completed settlements
    for (var settlement in previousSettlements) {
      final fNid = settlement.fromId.toLowerCase();
      final tNid = settlement.toId.toLowerCase();
      // fromId paid out (reduces their debt)
      if (settledMap.containsKey(fNid)) {
        settledMap[fNid] = _roundTo2Decimals(
          (settledMap[fNid] ?? 0.0) + settlement.amount,
        );
      }
      // toId received (reduces their credit due)
      if (settledMap.containsKey(tNid)) {
        settledMap[tNid] = _roundTo2Decimals(
          (settledMap[tNid] ?? 0.0) - settlement.amount,
        );
      }
    }

    // ===== STEP 4: CALCULATE FINAL NET BALANCE =====
    // net = paid - share + settled
    // positive: user is owed money | negative: user owes money

    final results = <String, UserBalanceDetails>{};
    for (var u in users) {
      final nid = u.id.toLowerCase();
      final paid = _roundTo2Decimals(paidMap[nid] ?? 0.0);
      final share = _roundTo2Decimals(shareMap[nid] ?? 0.0);
      final settled = _roundTo2Decimals(settledMap[nid] ?? 0.0);
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
