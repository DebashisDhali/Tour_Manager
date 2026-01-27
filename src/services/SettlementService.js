const { Decimal } = require('decimal.js'); // Assuming decimal.js for precision or just use JS numbers carefully

class SettlementService {
    /**
     * Calculates the minimized transactions to settle debts.
     * @param {Array} expenses - List of expense objects { payerId, amount, splitDetails: [{ userId, amount }] }
     * @param {Array} tourMembers - List of user IDs involved
     */
    static calculateSettlements(expenses, tourMembers) {
        // 1. Calculate Net Balance for each user
        const balances = {}; 
        tourMembers.forEach(id => balances[id] = 0);

        expenses.forEach(expense => {
            const payerId = expense.payerId;
            const amount = parseFloat(expense.amount);
            
            // Credit the payer (they paid, so they are owed money)
            balances[payerId] = (balances[payerId] || 0) + amount;

            // Debit the consumers
            expense.splitDetails.forEach(split => {
                const debtorId = split.userId;
                const share = parseFloat(split.amount);
                balances[debtorId] = (balances[debtorId] || 0) - share;
            });
        });

        // 2. Separate into Debtors and Creditors
        let debtors = [];
        let creditors = [];

        Object.keys(balances).forEach(userId => {
            const balance = balances[userId];
            // Floating point correction for near-zero
            if (Math.abs(balance) < 0.01) return;

            if (balance < 0) {
                debtors.push({ userId, amount: Math.abs(balance) });
            } else if (balance > 0) {
                creditors.push({ userId, amount: balance });
            }
        });

        // 3. Match Debtors and Creditors (The "Simplify Debts" Greedy Algorithm)
        const settlements = [];

        // Sort by amount (optional heuristic, often helps reduce tiny fragments)
        debtors.sort((a, b) => b.amount - a.amount);
        creditors.sort((a, b) => b.amount - a.amount);

        let i = 0; // debtor index
        let j = 0; // creditor index

        while (i < debtors.length && j < creditors.length) {
            let debtor = debtors[i];
            let creditor = creditors[j];

            // The amount to be settled is the minimum of what debtor owes and creditor needs
            let amount = Math.min(debtor.amount, creditor.amount);
            
            // Round to 2 decimals
            amount = Math.round(amount * 100) / 100;

            if (amount > 0) {
                settlements.push({
                    from: debtor.userId,
                    to: creditor.userId,
                    amount: amount
                });
            }

            // Update remaining amounts
            debtor.amount -= amount;
            creditor.amount -= amount;

            // If settled, move to next
            if (Math.abs(debtor.amount) < 0.01) i++;
            if (Math.abs(creditor.amount) < 0.01) j++;
        }

        return {
            balances,
            settlements
        };
    }
}

module.exports = SettlementService;
