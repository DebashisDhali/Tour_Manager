import '../../../data/local/app_database.dart';
import '../settlement_calculator.dart';
import 'base_calculator.dart';

class TourSettlementCalculator extends BaseSettlementCalculator {
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
    
    // Tour Specific: Program Incomes
    processProgramIncomes(incomes, users, paidMap, shareMap, itemLogs);

    // Tour Specific: Share Obligations (Explicit Splits)
    _calculateShareObligations(expenses, splits, users, shareMap, itemLogs);

    applyPreviousSettlements(previousSettlements, settledMap, itemLogs);
    return finalizeResults(users, paidMap, shareMap, settledMap, itemLogs);
  }

  void _calculateShareObligations(
    List<Expense> expenses,
    List<ExpenseSplit> splits,
    List<User> users,
    Map<String, double> shareMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    for (var split in splits) {
      final nid = split.userId.toLowerCase();
      if (shareMap.containsKey(nid)) {
        shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + split.amount);
        itemLogs[nid]?.add(BalanceItem(
          title: "Expense Share",
          amount: split.amount,
          type: 'share',
          isCredit: false,
        ));
      }
    }

    // Identify expenses without explicit splits (fallback to equal split)
    final Set<String> expensesWithSplits = splits.map((s) => s.expenseId).toSet();
    final List<Expense> expensesWithoutSplits = expenses
        .where((e) => !expensesWithSplits.contains(e.id))
        .toList();

    for (var e in expensesWithoutSplits) {
      if (users.isEmpty) continue;
      final amountPerPerson = roundTo2Decimals(e.amount / users.length);
      final totalDistributed = roundTo2Decimals(amountPerPerson * users.length);
      final remainder = roundTo2Decimals(e.amount - totalDistributed);

      for (int i = 0; i < users.length; i++) {
        final nid = users[i].id.toLowerCase();
        final extra = (i == 0) ? remainder : 0.0;
        final share = amountPerPerson + extra;
        shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + share);
        itemLogs[nid]?.add(BalanceItem(title: "${e.title} (shared)", amount: share, type: 'share', isCredit: false));
      }
    }
  }
}
