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
    // --- KEY FIX ---
    // In Mess mode: anything NOT explicitly 'fixed' is Bazar (meal).
    // This includes null/empty messCostType — handles legacy data too.
    // --- ROBUST CATEGORIZATION LOGIC ---
    // 1. Explicit Custom Splits take the HIGHEST priority.
    // If an expense has manually defined splits, we respect them regardless of type.
    final splitExpenseIds = splits.map((s) => s.expenseId.toLowerCase()).toSet();
    
    final mealExpenses = <Expense>[];
    final rentExpenses = <Expense>[];
    final customSplitExpenses = <Expense>[];

    for (var e in expenses) {
      if (splitExpenseIds.contains(e.id.toLowerCase())) {
        customSplitExpenses.add(e);
        continue;
      }

      final category = e.category.toLowerCase().trim();
      final type = e.messCostType?.toLowerCase().trim();
      
      // Strict Categorization for Mess mode:
      // 1. Rent: Category is 'rent' or type is 'fixed' (including maid, wifi, etc.)
      final isRent = category == 'rent' || 
                     type == 'fixed' || 
                     category == 'maid' || 
                     category == 'wifi' || 
                     category == 'others';

      if (isRent) {
        rentExpenses.add(e);
      } else {
        // 2. Bazar: Category is 'bazar' or default (meal-based)
        mealExpenses.add(e);
      }
    }

    // Process Custom Splits
    final relevantSplits = splits.where((s) => splitExpenseIds.contains(s.expenseId.toLowerCase())).toList();
    for (var split in relevantSplits) {
      final nid = split.userId.toLowerCase();
      if (shareMap.containsKey(nid)) {
        shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + split.amount);
        final exp = customSplitExpenses.firstWhere((e) => e.id.toLowerCase() == split.expenseId.toLowerCase(), orElse: () => expenses.first);
        itemLogs[nid]?.add(BalanceItem(title: "${exp.title} (Split)", amount: split.amount, type: 'share', isCredit: false));
      }
    }

    // Calculate total meals for participating users
    double totalMeals = 0.0;
    for (var u in users) {
      totalMeals += mealCounts?[u.id.toLowerCase()] ?? mealCounts?[u.id] ?? 0.0;
    }

    // 2. Distribute Bazar Expenses by meal count
    final totalBazarAmount = mealExpenses.fold(0.0, (s, e) => s + e.amount);
    final mealRate = totalMeals > 0 ? totalBazarAmount / totalMeals : 0.0;

    if (totalBazarAmount > 0 && totalMeals > 0) {
      double totalDistributedBazar = 0.0;
      final participatingNids = <String>[];
      
      for (var u in users) {
        final nid = u.id.toLowerCase();
        final count = mealCounts?[nid] ?? mealCounts?[u.id] ?? 0.0;
        if (count > 0) {
          participatingNids.add(nid);
          final bazarShare = roundTo2Decimals(mealRate * count);
          totalDistributedBazar += bazarShare;
          shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + bazarShare);
          itemLogs[nid]?.add(BalanceItem(title: "Meal Charge", amount: bazarShare, type: 'share', isCredit: false));
        }
      }
      
      // Distribute any rounding remainder to the first participant
      final bazarRemainder = roundTo2Decimals(totalBazarAmount - totalDistributedBazar);
      if (bazarRemainder.abs() > 0.001 && participatingNids.isNotEmpty) {
        final pNid = participatingNids.first;
        shareMap[pNid] = roundTo2Decimals((shareMap[pNid] ?? 0.0) + bazarRemainder);
        itemLogs[pNid]?.add(BalanceItem(title: "Bazar Rounding Comp.", amount: bazarRemainder, type: 'share', isCredit: false));
      }
    } else if (totalBazarAmount > 0 && totalMeals <= 0) {
      // Bazar cost exists but no meal records — distribute equally as fallback (avoid divide by zero)
      final fallbackShare = roundTo2Decimals(totalBazarAmount / users.length);
      for (var u in users) {
        shareMap[u.id] = roundTo2Decimals((shareMap[u.id] ?? 0.0) + fallbackShare);
        itemLogs[u.id]?.add(BalanceItem(title: "Bazar (pending meals)", amount: fallbackShare, type: 'share', isCredit: false));
      }
    }

    // 3. Distribute Rent Expenses equally among all members
    final totalRentAmount = rentExpenses.fold(0.0, (sum, e) => sum + e.amount);

    if (users.isNotEmpty && totalRentAmount > 0) {
      final rentPerPerson = roundTo2Decimals(totalRentAmount / users.length);
      final totalDistributed = roundTo2Decimals(rentPerPerson * users.length);
      final rentRemainder = roundTo2Decimals(totalRentAmount - totalDistributed);

      for (int idx = 0; idx < users.length; idx++) {
        final nid = users[idx].id.toLowerCase();
        final extraAmount = idx == 0 ? rentRemainder : 0.0;
        shareMap[nid] = roundTo2Decimals((shareMap[nid] ?? 0.0) + rentPerPerson + extraAmount);
        itemLogs[nid]?.add(BalanceItem(title: "Rent Share", amount: rentPerPerson + extraAmount, type: 'share', isCredit: false));
      }
    }
  }
}
