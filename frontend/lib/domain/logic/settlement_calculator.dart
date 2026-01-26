import 'dart:math';
import '../../data/local/app_database.dart';

class Settlement {
  final String payerName;
  final String receiverName;
  final double amount;

  Settlement({
    required this.payerName,
    required this.receiverName,
    required this.amount,
  });
}

class SettlementCalculator {
  
  /// Calculates the optimized settlement plan
  List<Settlement> calculate(List<Expense> expenses, List<ExpenseSplit> splits, List<User> users) {
    // 1. Calculate Balances
    final balances = <String, double>{};
    for (var u in users) {
      balances[u.id] = 0.0;
    }

    // Process expenses (Credits)
    for (var e in expenses) {
      balances[e.payerId] = (balances[e.payerId] ?? 0) + e.amount;
    }

    // Process splits (Debits)
    for (var s in splits) {
       balances[s.userId] = (balances[s.userId] ?? 0) - s.amount;
    }

    // 2. Separate Debtors and Creditors
    final debtors = <_BalanceItem>[];
    final creditors = <_BalanceItem>[];

    balances.forEach((userId, amount) {
      if (amount < -0.01) {
        debtors.add(_BalanceItem(userId, amount)); // Amount is negative
      } else if (amount > 0.01) {
        creditors.add(_BalanceItem(userId, amount));
      }
    });

    // Sort to optimize (Greedy)
    debtors.sort((a, b) => a.amount.compareTo(b.amount)); // Ascending (most negative first)
    creditors.sort((a, b) => b.amount.compareTo(a.amount)); // Descending (most positive first)

    final settlements = <Settlement>[];
    int i = 0; // Debtor ptr
    int j = 0; // Creditor ptr

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];

      // Debtor amount is negative, we need absolute value
      double amount = min(debtor.amount.abs(), creditor.amount);
      
      // Round to 2 decimals
      amount = (amount * 100).round() / 100;

      // Find user names
      final debtorName = users.firstWhere((u) => u.id == debtor.userId).name;
      final creditorName = users.firstWhere((u) => u.id == creditor.userId).name;

      settlements.add(Settlement(
        payerName: debtorName,
        receiverName: creditorName,
        amount: amount,
      ));

      // Update remaining
      debtor.amount += amount; // Add positive to make less negative
      creditor.amount -= amount; // Subtract to make less positive

      // Check if settled
      if (debtor.amount.abs() < 0.01) i++;
      if (creditor.amount.abs() < 0.01) j++;
    }

    return settlements;
  }
}

class _BalanceItem {
  final String userId;
  double amount;
  _BalanceItem(this.userId, this.amount);
}
