import '../../../data/local/app_database.dart';
import '../settlement_calculator.dart';

abstract class BaseSettlementCalculator {
  /// Rounds to 2 decimal places with proper floating point handling
  double roundTo2Decimals(double value) {
    return (value * 100).round() / 100;
  }

  /// Main calculation method to be implemented by specific calculators
  Map<String, UserBalanceDetails> calculateBalances({
    required List<Expense> expenses,
    required List<ExpenseSplit> splits,
    required List<ExpensePayer> expensePayers,
    required List<User> users,
    required List<Settlement> previousSettlements,
    Map<String, double>? mealCounts,
    List<ProgramIncome>? incomes,
  });

  /// Helper to initialize balance maps for all users
  void initializeBalanceMaps(
    List<User> users,
    Map<String, double> paidMap,
    Map<String, double> shareMap,
    Map<String, double> settledMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    for (var u in users) {
      final nid = u.id.toLowerCase();
      paidMap[nid] = 0.0;
      shareMap[nid] = 0.0;
      settledMap[nid] = 0.0;
      itemLogs[nid] = [];
    }
  }

  /// Common logic for calculating paid amounts from expenses and expensePayers
  void calculatePaidAmounts(
    List<Expense> expenses,
    List<ExpensePayer> expensePayers,
    Map<String, double> paidMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    final Set<String> expensesWithPayerRecords = {};

    for (var ep in expensePayers) {
      expensesWithPayerRecords.add(ep.expenseId.toLowerCase());
      final nid = ep.userId.toLowerCase();
      paidMap[nid] = roundTo2Decimals((paidMap[nid] ?? 0.0) + ep.amount);
      itemLogs[nid]?.add(BalanceItem(title: "Payment", amount: ep.amount, type: 'paid', isCredit: true));
    }

    for (var e in expenses) {
      final eid = e.id.toLowerCase();
      if (!expensesWithPayerRecords.contains(eid) && e.payerId != null) {
        final nid = e.payerId!.toLowerCase();
        paidMap[nid] = roundTo2Decimals((paidMap[nid] ?? 0.0) + e.amount);
        itemLogs[nid]?.add(BalanceItem(title: e.title, amount: e.amount, type: 'paid', isCredit: true));
      }
    }
  }

  /// Deduplicates expenses to prevent double counting (sync ghosts)
  Map<String, Expense> deduplicateExpenses(List<Expense> expenses) {
    final Map<String, Expense> expensesToProcess = {};
    for (var e in expenses) {
      if (!expensesToProcess.containsKey(e.id)) {
        expensesToProcess[e.id] = e;
      }
    }
    return expensesToProcess;
  }

  /// Deduplicates splits to prevent double counting
  List<ExpenseSplit> deduplicateSplits(List<ExpenseSplit> splits) {
    final Map<String, ExpenseSplit> uniqueSplits = {};
    for (var s in splits) {
      if (!uniqueSplits.containsKey(s.id)) {
        uniqueSplits[s.id] = s;
      }
    }
    return uniqueSplits.values.toList();
  }

  /// Common logic for accounting for previous settlements
  void applyPreviousSettlements(
    List<Settlement> previousSettlements,
    Map<String, double> settledMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    for (var settlement in previousSettlements) {
      final fNid = settlement.fromId;
      final tNid = settlement.toId;
      if (settledMap.containsKey(fNid)) {
        settledMap[fNid] = roundTo2Decimals((settledMap[fNid] ?? 0.0) + settlement.amount);
        itemLogs[fNid]?.add(BalanceItem(title: "Settlement Paid Out", amount: settlement.amount, type: 'settled', isCredit: true));
      }
      if (settledMap.containsKey(tNid)) {
        settledMap[tNid] = roundTo2Decimals((settledMap[tNid] ?? 0.0) - settlement.amount);
        itemLogs[tNid]?.add(BalanceItem(title: "Settlement Received", amount: settlement.amount, type: 'settled', isCredit: false));
      }
    }
  }

  /// Finalizes the results into a map of UserBalanceDetails
  Map<String, UserBalanceDetails> finalizeResults(
    List<User> users,
    Map<String, double> paidMap,
    Map<String, double> shareMap,
    Map<String, double> settledMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    final results = <String, UserBalanceDetails>{};
    for (var u in users) {
      final nid = u.id.toLowerCase();
      final paid = roundTo2Decimals(paidMap[nid] ?? paidMap[u.id] ?? 0.0);
      final share = roundTo2Decimals(shareMap[nid] ?? shareMap[u.id] ?? 0.0);
      final settled = roundTo2Decimals(settledMap[nid] ?? settledMap[u.id] ?? 0.0);
      final net = roundTo2Decimals(paid - share + settled);

      results[nid] = UserBalanceDetails(
        paid: paid,
        share: share,
        settled: settled,
        net: net,
        items: List.from(itemLogs[nid] ?? itemLogs[u.id] ?? []),
      );
    }
    return results;
  }

  void processProgramIncomes(
    List<ProgramIncome>? incomes,
    List<User> users,
    Map<String, double> paidMap,
    Map<String, double> shareMap,
    Map<String, List<BalanceItem>> itemLogs,
  ) {
    double totalSharedIncome = 0.0;
    if (incomes != null) {
      for (var income in incomes) {
        final source = (income.source ?? '').toLowerCase();
        if (source.contains('brought forward') || 
            source.contains('common') || 
            source.contains('fund') || 
            source.contains('balance') ||
            source.contains('carried')) {
          totalSharedIncome += income.amount;
        } else {
          final nid = income.collectedBy;
          paidMap[nid] = roundTo2Decimals((paidMap[nid] ?? 0.0) - income.amount);
          itemLogs[nid]?.add(BalanceItem(title: "Collected: ${income.source}", amount: income.amount, type: 'paid', isCredit: false));
        }
      }
    }

    if (totalSharedIncome > 0 && users.isNotEmpty) {
      final incomePerMember = roundTo2Decimals(totalSharedIncome / users.length);
      final totalDistributed = roundTo2Decimals(incomePerMember * users.length);
      final remainder = roundTo2Decimals(totalSharedIncome - totalDistributed);

      for (int i = 0; i < users.length; i++) {
        final nid = users[i].id;
        final extra = (i == 0) ? remainder : 0.0;
        final shareReduction = incomePerMember + extra;
        shareMap[nid] = (shareMap[nid] ?? 0.0) - shareReduction;
        itemLogs[nid]?.add(BalanceItem(title: "Shared Income Distri.", amount: shareReduction, type: 'share', isCredit: true));
      }
    }
  }
}
