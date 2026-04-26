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

    print("DEBUG: [TourCalculator] Calculating for ${users.length} users. Purpose: Tour/Project");
    for(var u in users) print("DEBUG:   - User: ${u.id} (${u.name})");

    initializeBalanceMaps(users, paidMap, shareMap, settledMap, itemLogs);
    calculatePaidAmounts(expenses, expensePayers, paidMap, itemLogs);
    
    // Tour Specific: Program Incomes
    processProgramIncomes(incomes, users, paidMap, shareMap, itemLogs);

    // Tour Specific: Share Obligations (Explicit Splits)
    _calculateShareObligations(expenses, splits, users, shareMap, itemLogs);

    applyPreviousSettlements(previousSettlements, settledMap, itemLogs);
    final results = finalizeResults(users, paidMap, shareMap, settledMap, itemLogs);
    results.forEach((uid, details) {
      print("DEBUG:   - Result for $uid: Paid=${details.paid}, Share=${details.share}, Net=${details.net}");
    });
    return results;
  }

  void _calculateShareObligations(
    List<Expense> expenses,
    List<ExpenseSplit> splits,
    List<User> users,
    Map<String, double> shareMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    if (users.isEmpty) return;

    // Group splits by expenseId for efficient lookup
    final Map<String, List<ExpenseSplit>> splitsByExpense = {};
    for (var s in splits) {
      final eid = s.expenseId.toLowerCase();
      splitsByExpense.putIfAbsent(eid, () => []).add(s);
    }

    for (var e in expenses) {
      final eid = e.id.toLowerCase();
      final eSplits = splitsByExpense[eid] ?? [];
      print("DEBUG:   - Processing Expense: ${e.title} ($eid), Amount: ${e.amount}");
      
      double assignedAmount = 0.0;
      for (var split in eSplits) {
        final nid = split.userId.toLowerCase();
        if (shareMap.containsKey(nid)) {
          final amount = split.amount;
          assignedAmount += amount;
          shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + amount);
          print("DEBUG:     * Explicit Split: $nid gets $amount");
          itemLogs[nid]?.add(BalanceItem(
            title: "${e.title} (Split)",
            amount: amount,
            type: 'share',
            isCredit: false,
          ));
        } else {
          print("DEBUG:     * WARNING: Split user $nid not in shareMap!");
        }
      }

      // Distribute any remaining (unassigned) amount equally
      final unassigned = roundTo2Decimals(e.amount - assignedAmount);
      print("DEBUG:     * Unassigned: $unassigned");
      if (unassigned > 0.005) {
        final amountPerPerson = roundTo2Decimals(unassigned / users.length);
        final totalDistributed = roundTo2Decimals(amountPerPerson * users.length);
        final remainder = roundTo2Decimals(unassigned - totalDistributed);

        for (int i = 0; i < users.length; i++) {
          final nid = users[i].id.toLowerCase();
          final extra = (i == 0) ? remainder : 0.0;
          final share = amountPerPerson + extra;
          shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + share);
          itemLogs[nid]?.add(BalanceItem(
            title: eSplits.isEmpty ? "${e.title} (shared)" : "${e.title} (unassigned part)",
            amount: share,
            type: 'share',
            isCredit: false,
          ));
        }
      }
    }
  }
}
