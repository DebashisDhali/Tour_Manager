import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../domain/logic/settlement_calculator.dart';
import '../../data/providers/app_providers.dart';
import '../../main.dart';
import 'final_receipt_screen.dart';

class SettlementScreen extends ConsumerWidget {
  final String tourId;
  const SettlementScreen({super.key, required this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    
    return FutureBuilder(
      future: Future.wait([
        db.getAllUsers(),
        (db.select(db.expenses)..where((t) => t.tourId.equals(tourId))).get(),
        db.select(db.expenseSplits).get(),
        (db.select(db.tours)..where((t) => t.id.equals(tourId))).getSingle(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final users = snapshot.data![0] as List<User>;
        final expenses = snapshot.data![1] as List<Expense>;
        final allSplits = snapshot.data![2] as List<ExpenseSplit>;
        final tour = snapshot.data![3] as Tour;
        
        final expenseIds = expenses.map((e) => e.id).toSet();
        final tourSplits = allSplits.where((s) => expenseIds.contains(s.expenseId)).toList();

        final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);
        final averageCost = users.isEmpty ? 0.0 : totalCost / users.length;

        final calculator = SettlementCalculator();
        final instructions = calculator.calculate(expenses, tourSplits, users);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Analysis Summary Section ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionTitle("Tour Analysis"),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => FinalReceiptScreen(
                      tour: tour,
                      users: users,
                      expenses: expenses,
                      splits: tourSplits,
                      settlementInstructions: instructions,
                    )));
                  },
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text("Export Statement", style: TextStyle(fontSize: 12)),
                )
              ],
            ),

            Card(
              elevation: 0,
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem("Total Cost", "${totalCost.toStringAsFixed(0)} ৳", Icons.account_balance_wallet_outlined),
                        Container(width: 1, height: 40, color: Colors.teal.shade200),
                        _buildStatItem("Per Person", "${averageCost.toStringAsFixed(0)} ৳", Icons.person_outline),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- Logic Explanation Section ---
            _buildSectionTitle("How it's Calculated"),
            InkWell(
              onTap: () => _showAlgorithmExplanation(context),
              borderRadius: BorderRadius.circular(16),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildRuleItem(Icons.auto_awesome, "Greedy Minimization", "We use a smart algorithm that reduces the number of transactions, so most people only have to pay once."),
                      const Divider(height: 24),
                      _buildRuleItem(Icons.balance, "Equal Distribution", "The total tour cost is divided equally among all group members."),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // --- Contribution Summary Section ---
            _buildSectionTitle("Contribution Summary"),
            ...users.map((u) {
              final paid = expenses.where((e) => e.payerId == u.id).fold(0.0, (sum, e) => sum + e.amount);
              final share = tourSplits.where((s) => s.userId == u.id).fold(0.0, (sum, s) => sum + s.amount);
              final balance = paid - share;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade100),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade50,
                    child: Text(u.name[0], style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Paid: ${paid.toStringAsFixed(0)} ৳ | Share: ${share.toStringAsFixed(0)} ৳", 
                    style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    "${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)} ৳",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: balance >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 24),

            const SizedBox(height: 24),
            _buildSectionTitle("Settlement Plan | লেনদেন গাইড"),

            if (instructions.isEmpty)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
                    const SizedBox(height: 12),
                    const Text("Perfectly Settled!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              )
            else ...[
              _buildVisualFlow(instructions),
            ],
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.teal, size: 20),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF006D6D))),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRuleItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  void _showAlgorithmExplanation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            const Text("হিসাব নিকাশ কিভাবে হয়? 🧠", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
            const Text("How calculations work", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                   _buildStep(1, "ব্যালেন্স ক্যালকুলেশন", "প্রথমে অ্যাপটি দেখে যে ট্যুরে কার কত টাকা দেওয়ার কথা ছিল এবং সে বাস্তবে কত টাকা দিয়েছে। (Paid - Share = Balance)"),
                   _buildStep(2, "পাওনাদার ও দেনাদার আলাদা করা", "যাদের ব্যালেন্স পজিটিভ তারা টাকা পাবে (Creditors), আর যাদের নেগেটিভ তারা টাকা দিবে (Debtors)।"),
                   _buildStep(3, "Greedy Flow Minimization", "আমরা একটি স্মার্ট অ্যালগরিদম ব্যবহার করি যা সবচেয়ে বড় দেনাদারকে সবচেয়ে বড় পাওনাদারের সাথে মিলিয়ে দেয়। এর ফলে লেনদেনের সংখ্যা (Number of Transactions) সবচেয়ে কম হয়।"),
                   _buildStep(4, "সহজ সমাধান", "এর উদ্দেশ্য হলো যেন ট্যুর শেষে সবাইকে সবার হাতে টাকা দিতে না হয়, বরং মাত্র কয়েকজনের মধ্যে লেনদেন করলেই সবার হিসাব মিলে যায়।"),
                   const SizedBox(height: 24),
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
                     child: const Column(
                       children: [
                         Text("উদাহরণ:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                         SizedBox(height: 8),
                         Text("আবির ৫০০৳ পায়, আর সজল ৫০০৳ দিবে। অ্যালগরিদম সজলকে সরাসরি আবিরকে টাকা দিতে বলবে, মাঝখানে অন্য কারো কোনো ঝামেলা থাকবে না।", 
                           textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                       ],
                     ),
                   )
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("বুঝেছি!"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int no, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 12, backgroundColor: Colors.teal, child: Text(no.toString(), style: const TextStyle(fontSize: 12, color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildUserAvatar(String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.teal,
          child: Text(name[0], style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildVisualFlow(List<Settlement> instructions) {
    final groupedByPayer = <String, List<Settlement>>{};
    for (var s in instructions) {
      groupedByPayer.putIfAbsent(s.payerName, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Visual Payment Network | পেমেন্ট গ্রাফ"),
        ...groupedByPayer.entries.map((entry) {
          final payer = entry.key;
          final receivers = entry.value;

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.teal.shade100, width: 1),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [Colors.teal.shade50.withOpacity(0.3), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildUserAvatar(payer),
                  const SizedBox(width: 12),
                  _buildCustomArrow(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...receivers.map((r) => Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade100),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "${r.amount.toStringAsFixed(0)} ৳",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_right, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              _buildSmallAvatar(r.receiverName),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCustomArrow() {
    return Column(
      children: [
        Container(
          width: 2,
          height: 30,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade100, Colors.teal],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const Icon(Icons.arrow_drop_down, color: Colors.teal, size: 16),
      ],
    );
  }

  Widget _buildSmallAvatar(String name) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.teal.shade100,
          child: Text(name[0], style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
