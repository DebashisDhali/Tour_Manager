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

class SettlementCalculator {
  
  /// Calculates the optimized settlement plan
  List<SettlementInstruction> calculate(
    List<Expense> expenses, 
    List<ExpenseSplit> splits, 
    List<ExpensePayer> expensePayers,
    List<User> users,
    List<Settlement> previousSettlements
  ) {
    // 1. Calculate Balances
    final balances = <String, double>{};
    for (var u in users) {
      balances[u.id] = 0.0;
    }

    // Process expenses (Credits - who PAID)
    final expensesWithPayerRecords = expensePayers.map((p) => p.expenseId).toSet();
    
    // 1. First process explicit payer records (New System)
    for (var ep in expensePayers) {
      balances[ep.userId] = (balances[ep.userId] ?? 0) + ep.amount;
    }

    // 2. Fallback for legacy expenses without records in ExpensePayers table
    for (var e in expenses) {
       if (!expensesWithPayerRecords.contains(e.id) && e.payerId != null) {
          balances[e.payerId!] = (balances[e.payerId!] ?? 0) + e.amount;
       }
    }

    // Process splits (Debits - who owes)
    for (var s in splits) {
       balances[s.userId] = (balances[s.userId] ?? 0) - s.amount;
    }

    // Process Previous Settlements (Adjustments)
    // If A paid B 500, A gets +500 (Credit) and B gets -500 (Debit)
    for (var s in previousSettlements) {
      balances[s.fromId] = (balances[s.fromId] ?? 0) + s.amount;
      balances[s.toId] = (balances[s.toId] ?? 0) - s.amount;
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

    final settlements = <SettlementInstruction>[];
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
      final debtorUser = users.firstWhere((u) => u.id == debtor.userId);
      final creditorUser = users.firstWhere((u) => u.id == creditor.userId);

      settlements.add(SettlementInstruction(
        payerId: debtorUser.id,
        payerName: debtorUser.name,
        receiverId: creditorUser.id,
        receiverName: creditorUser.name,
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
