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

class SettlementCalculator {
  
  /// Calculates the optimized settlement plan
  List<SettlementInstruction> calculate(
    List<Expense> expenses, 
    List<ExpenseSplit> splits, 
    List<ExpensePayer> expensePayers,
    List<User> users,
    List<Settlement> previousSettlements, {
    String? purpose,
    Map<String, double>? mealCounts, // userId -> mealCount
    List<ProgramIncome>? incomes,
  }) {
    // 1. Calculate Balances
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

    // 2. Separate Debtors and Creditors
    final debtors = <_BalanceItem>[];
    final creditors = <_BalanceItem>[];

    balanceMap.forEach((userId, details) {
      final amount = details.net;
      if (amount < -0.01) {
        debtors.add(_BalanceItem(userId, amount)); // Amount is negative
      } else if (amount > 0.01) {
        creditors.add(_BalanceItem(userId, amount));
      }
    });

    // Sort to optimize (Greedy)
    debtors.sort((a, b) => a.amount.compareTo(b.amount)); // Ascending (most negative first)
    creditors.sort((a, b) => b.amount.compareTo(a.amount)); // Descending (most positive first)

    final userMap = {for (var u in users) u.id: u};

    final settlements = <SettlementInstruction>[];
    int i = 0; // Debtor ptr
    int j = 0; // Creditor ptr

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];

      double amount = min(debtor.amount.abs(), creditor.amount);
      amount = (amount * 100).round() / 100;

      final debtorUser = userMap[debtor.userId]!;
      final creditorUser = userMap[creditor.userId]!;

      settlements.add(SettlementInstruction(
        payerId: debtorUser.id,
        payerName: debtorUser.name,
        receiverId: creditorUser.id,
        receiverName: creditorUser.name,
        amount: amount,
      ));

      debtor.amount += amount;
      creditor.amount -= amount;

      if (debtor.amount.abs() < 0.01) i++;
      if (creditor.amount.abs() < 0.01) j++;
    }

    return settlements;
  }

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

    for (var u in users) {
      paidMap[u.id] = 0.0;
      shareMap[u.id] = 0.0;
      settledMap[u.id] = 0.0;
    }

    // Credits (Paid)
    // 1. Explicit expense payer records
    final expensesWithPayerRecords = expensePayers.map((p) => p.expenseId).toSet();
    for (var ep in expensePayers) {
      paidMap[ep.userId] = (paidMap[ep.userId] ?? 0) + ep.amount;
    }
    // 2. Fallback payer matching
    for (var e in expenses) {
       if (!expensesWithPayerRecords.contains(e.id) && e.payerId != null) {
          paidMap[e.payerId!] = (paidMap[e.payerId!] ?? 0) + e.amount;
       }
    }
    // 3. Program Incomes (Deposits/Collected Funds)
    if (incomes != null) {
      for (var income in incomes) {
        paidMap[income.collectedBy] = (paidMap[income.collectedBy] ?? 0) + income.amount;
      }
    }

    // Debits (Share)
    bool hasMealData = purpose?.toLowerCase() == 'mess' && mealCounts != null && mealCounts!.values.any((v) => v > 0);
    bool hasMealExpenses = purpose?.toLowerCase() == 'mess' && expenses.any((e) => e.messCostType == 'meal');
    
    if (hasMealData || hasMealExpenses) {
      final fixedAmount = expenses.where((e) => e.messCostType == 'fixed').fold(0.0, (s, e) => s + e.amount);
      final perMemberFixed = users.isNotEmpty ? fixedAmount / users.length : 0.0;
      final totalMealCost = expenses.where((e) => e.messCostType == 'meal').fold(0.0, (s, e) => s + e.amount);
      final totalMeals = mealCounts?.values.fold(0.0, (s, c) => s + c) ?? 0.0;
      final mealRate = totalMeals > 0 ? totalMealCost / totalMeals : 0.0;

      final messManagedIds = expenses.where((e) => e.messCostType != null).map((e) => e.id).toSet();

      for (var u in users) {
        final count = mealCounts?[u.id] ?? 0.0;
        shareMap[u.id] = perMemberFixed + (mealRate * count);
      }

      for (var s in splits) {
        if (!messManagedIds.contains(s.expenseId)) {
          shareMap[s.userId] = (shareMap[s.userId] ?? 0) + s.amount;
        }
      }
    } else {
      for (var s in splits) {
         shareMap[s.userId] = (shareMap[s.userId] ?? 0) + s.amount;
      }
    }

    // Settlement Adjustments
    for (var s in previousSettlements) {
      settledMap[s.fromId] = (settledMap[s.fromId] ?? 0) + s.amount;
      settledMap[s.toId] = (settledMap[s.toId] ?? 0) - s.amount;
    }

    final results = <String, UserBalanceDetails>{};
    for (var u in users) {
      final p = paidMap[u.id] ?? 0;
      final s = shareMap[u.id] ?? 0;
      final st = settledMap[u.id] ?? 0;
      results[u.id] = UserBalanceDetails(
        paid: p,
        share: s,
        settled: st,
        net: p - s + st,
      );
    }
    return results;
  }
}

class _BalanceItem {
  final String userId;
  double amount;
  _BalanceItem(this.userId, this.amount);
}
