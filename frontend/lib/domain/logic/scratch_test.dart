void main() {
  // Simulation of the greedy settlement algorithm
  final debtors = [{'id': 'dd', 'amount': -250.0}];
  final creditors = [{'id': 'wasim', 'amount': 250.0}];
  
  print("\nSettlement Guide Simulation:");
  int i = 0; int j = 0;
  while(i < debtors.length && j < creditors.length) {
    double amount = (debtors[i]['amount'] as double).abs();
    if (amount > (creditors[j]['amount'] as double)) amount = (creditors[j]['amount'] as double);
    
    print("Instruction: ${debtors[i]['id']} pays ${creditors[j]['id']} \$$amount");
    i++; j++;
  }
}
