import '../../../data/local/app_database.dart';
import '../settlement_calculator.dart';
import 'base_calculator.dart';

class MessSettlementCalculator extends BaseSettlementCalculator {
  @override
  Map<String, UserBalanceDetails> calculateBalances({
    required List<Expense> expenses,
    required List<ExpenseSplit> splits,
    required List<ExpensePayer> expensePayers,
    required List<User> users,
    required List<Settlement> previousSettlements,
    Map<String, double>? mealCounts,
    List<ProgramIncome>? incomes,
  }) {
    final paidMap = <String, double>{};
    final shareMap = <String, double>{};
    final settledMap = <String, double>{};
    final Map<String, List<BalanceItem>> itemLogs = {};

    initializeBalanceMaps(users, paidMap, shareMap, settledMap, itemLogs);
    calculatePaidAmounts(expenses, expensePayers, paidMap, itemLogs);
    
    // Calculate total meals
    double totalMeals = 0.0;
    if (mealCounts != null) {
      for (var u in users) {
        totalMeals += mealCounts[u.id] ?? 0.0;
      }
    }

    if (totalMeals <= 0) {
      // User says: "Jatokkhn kno meal entry hbe ... total hisab er dorkar nai"
      // We set share = paid to ensure net balance is 0 for everyone until meals start
      for (var u in users) {
        final nid = u.id;
        final paid = roundTo2Decimals(paidMap[nid] ?? 0.0);
        if (paid.abs() > 0.001) {
          shareMap[nid] = paid;
          itemLogs[nid]?.add(BalanceItem(
            title: "Pending (No Meals entered yet)", 
            amount: paid, 
            type: 'share', 
            isCredit: false
          ));
        }
      }
      // We still apply previous settlements as they are actual money movements
      applyPreviousSettlements(previousSettlements, settledMap, itemLogs);
      return finalizeResults(users, paidMap, shareMap, settledMap, itemLogs);
    }

    // Mess Specific: Program Incomes (Collections/Brought forward)
    processProgramIncomes(incomes, users, paidMap, shareMap, itemLogs);
    
    // Mess Specific: Share Obligations (Meal-based + Fixed)
    _calculateMessShareObligations(expenses, splits, users, mealCounts, shareMap, itemLogs);

    applyPreviousSettlements(previousSettlements, settledMap, itemLogs);
    return finalizeResults(users, paidMap, shareMap, settledMap, itemLogs);
  }

  void _calculateMessShareObligations(
    List<Expense> expenses,
    List<ExpenseSplit> splits,
    List<User> users,
    Map<String, double>? mealCounts,
    Map<String, double> shareMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    final Set<String> expensesWithSplits = splits.map((s) => s.expenseId).toSet();

    // 1. Handle Explicit Splits (High Priority)
    for (var split in splits) {
      final nid = split.userId;
      if (shareMap.containsKey(nid)) {
         shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + split.amount);
         itemLogs[nid]?.add(BalanceItem(title: "Custom Split", amount: split.amount, type: 'share', isCredit: false));
      }
    }

    // Identify expenses that were NOT handled by splits
    final List<Expense> unhandledExpenses = expenses
        .where((e) => !expensesWithSplits.contains(e.id))
        .toList();

    // Only count meals for the users we are currently calculating for
    double totalMeals = 0.0;
    for (var u in users) {
      totalMeals += mealCounts?[u.id] ?? 0.0;
    }

    // 2. Distribute Unhandled Meal Costs
    // Since totalMeals > 0 (checked in caller), we treat unspecified (null) as meal (Bazar)
    final mealExpenses = unhandledExpenses.where((e) => 
      e.messCostType == 'meal' || e.messCostType == null
    ).toList();
    final totalMealCost = mealExpenses.fold(0.0, (sum, e) => sum + e.amount);

    if (totalMealCost > 0) {
      final mealRate = totalMealCost / totalMeals;
      double totalDistributedMeal = 0.0;
      final participatingNids = <String>[];
      
      for (var u in users) {
        final nid = u.id;
        final count = mealCounts?[nid] ?? 0.0;
        if (count > 0) {
          participatingNids.add(nid);
          final mealShare = roundTo2Decimals(mealRate * count);
          totalDistributedMeal += mealShare;
          shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + mealShare);
          itemLogs[nid]?.add(BalanceItem(title: "Meal Cost Share", amount: mealShare, type: 'share', isCredit: false));
        }
      }
      
      final mealRemainder = roundTo2Decimals(totalMealCost - totalDistributedMeal);
      if (mealRemainder.abs() > 0.001 && participatingNids.isNotEmpty) {
        final pNid = participatingNids.first;
        shareMap[pNid] = roundTo2Decimals((shareMap[pNid] ?? 0.0) + mealRemainder);
        itemLogs[pNid]?.add(BalanceItem(title: "Meal Rounding Comp.", amount: mealRemainder, type: 'share', isCredit: false));
      }
    }

    // 3. Identify Fixed Expenses
    final fixedExpenses = unhandledExpenses.where((e) => 
      e.messCostType == 'fixed'
    ).toList();
    
    final totalFixedCost = fixedExpenses.fold(0.0, (sum, e) => sum + e.amount);

    if (users.isNotEmpty && totalFixedCost > 0) {
      final fixedPerMember = roundTo2Decimals(totalFixedCost / users.length);
      final totalDistributed = roundTo2Decimals(fixedPerMember * users.length);
      final fixedRemainder = roundTo2Decimals(totalFixedCost - totalDistributed);

      for (int idx = 0; idx < users.length; idx++) {
        final nid = users[idx].id;
        final extraAmount = idx == 0 ? fixedRemainder : 0.0;
        shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + fixedPerMember + extraAmount);
        itemLogs[nid]?.add(BalanceItem(title: "Fixed Cost Share", amount: fixedPerMember + extraAmount, type: 'share', isCredit: false));
      }
    }
  }
}
