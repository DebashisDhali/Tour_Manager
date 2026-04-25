import '../../../data/local/app_database.dart';
import '../settlement_calculator.dart';
import 'base_calculator.dart';
import 'tour_calculator.dart';

/// Specialized calculator for Events. 
/// Currently uses the same logic as Tour but separated for future customization and 100% accuracy.
class EventSettlementCalculator extends BaseSettlementCalculator {
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
    final collectedMap = <String, double>{};
    final spentMap = <String, double>{};
    final settledMap = <String, double>{};
    final Map<String, List<BalanceItem>> itemLogs = {};

    initializeBalanceMaps(users, collectedMap, spentMap, settledMap, itemLogs);
    // Previous settlements (already handled by base class but we track it in settledMap)
    applyPreviousSettlements(previousSettlements, settledMap, itemLogs);

    // 1. Calculate Collected Funds (from ProgramIncomes)
    if (incomes != null) {
      for (var income in incomes) {
        final nid = income.collectedBy;
        if (collectedMap.containsKey(nid)) {
          collectedMap[nid] = roundTo2Decimals(collectedMap[nid]! + income.amount);
          itemLogs[nid]?.add(BalanceItem(
            title: "Collected: ${income.source}",
            amount: income.amount,
            type: 'collected',
            isCredit: false,
          ));
        }
      }
    }

    // 2. Calculate Spent Amounts (from Expenses paid by member)
    final Set<String> expensesWithPayerRecords = {};
    for (var ep in expensePayers) {
      expensesWithPayerRecords.add(ep.expenseId);
      final nid = ep.userId;
      if (spentMap.containsKey(nid)) {
        spentMap[nid] = roundTo2Decimals(spentMap[nid]! + ep.amount);
        itemLogs[nid]?.add(BalanceItem(
          title: "Spent (Payment)",
          amount: ep.amount,
          type: 'spent',
          isCredit: true,
        ));
      }
    }
    for (var e in expenses) {
      if (!expensesWithPayerRecords.contains(e.id) && e.payerId != null) {
        final nid = e.payerId!;
        if (spentMap.containsKey(nid)) {
          spentMap[nid] = roundTo2Decimals(spentMap[nid]! + e.amount);
          itemLogs[nid]?.add(BalanceItem(
            title: "Spent: ${e.title}",
            amount: e.amount,
            type: 'spent',
            isCredit: true,
          ));
        }
      }
    }

    // 3. Step 1: Event Totals
    double totalFund = roundTo2Decimals(collectedMap.values.fold(0, (s, v) => s + v));
    double totalExpense = roundTo2Decimals(spentMap.values.fold(0, (s, v) => s + v));
    double surplusOrDeficit = roundTo2Decimals(totalFund - totalExpense);

    if (users.isEmpty) return {};

    // 4. Step 2 & 4: Distribution calculation
    // surplusShare = (TotalFund - TotalExpense) / N
    double surplusShare = roundTo2Decimals(surplusOrDeficit / users.length);
    double totalDistributedOutcome = roundTo2Decimals(surplusShare * users.length);
    double outcomeRemainder = roundTo2Decimals(surplusOrDeficit - totalDistributedOutcome);

    final results = <String, UserBalanceDetails>{};
    for (int i = 0; i < users.length; i++) {
      final u = users[i];
      final nid = u.id;
      final extra = (i == 0) ? outcomeRemainder : 0.0;
      final memberSurplusShare = roundTo2Decimals(surplusShare + extra);
      
      final collected = collectedMap[nid]!;
      final spent = spentMap[nid]!;
      final settled = settledMap[nid]!;
      
      // Step 3 & 4 (Combined): 
      // Final Balance (User convention: >0 Owes) = (collected - spent) - (ExpenseShare? No, SurplusShare)
      // Correct Zero-Sum Logic: Balance = (collected - spent) - (TotalFund - TotalExpense)/N
      // App Net = - (Balance) + settled
      // App Net = (spent - collected) + memberSurplusShare + settled
      
      final net = roundTo2Decimals((spent - collected) + memberSurplusShare + settled);
      
      // Map to UserBalanceDetails for UI compatibility
      // 'paid' -> mapped to 'spent'
      // 'share' -> mapped to 'collected - memberSurplusShare'
      results[nid] = UserBalanceDetails(
        paid: spent,
        share: roundTo2Decimals(collected - memberSurplusShare),
        settled: settled,
        net: net,
        items: List.from(itemLogs[nid]!),
      );
      
      // Add individual logs for the breakdown UI
      itemLogs[nid]?.add(BalanceItem(
        title: "Share of ${surplusOrDeficit >= 0 ? 'Surplus' : 'Deficit'}",
        amount: memberSurplusShare.abs(),
        type: 'outcome',
        isCredit: surplusOrDeficit >= 0,
      ));
    }

    return results;
  }
}
