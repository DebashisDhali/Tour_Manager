import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart' as models;
import '../../domain/logic/settlement_calculator.dart';
import '../../data/providers/app_providers.dart';
import '../../main.dart';
import 'final_receipt_screen.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../domain/logic/purpose_config.dart';

class SettlementScreen extends ConsumerWidget {
  final String tourId;
  const SettlementScreen({super.key, required this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final config = PurposeConfig.getConfig(currentUserAsync.value?.purpose);

    final usersAsync = ref.watch(tourUsersProvider(tourId));
    final expensesAsync = ref.watch(tourExpensesProvider(tourId));
    final splitsAsync = ref.watch(tourSplitsProvider(tourId));
    final tourAsync = ref.watch(singleTourProvider(tourId));
    final settlementsAsync = ref.watch(tourSettlementsProvider(tourId));
    final payersAsync = ref.watch(tourPayersProvider(tourId));

    if (usersAsync.isLoading || expensesAsync.isLoading || splitsAsync.isLoading || 
        tourAsync.isLoading || settlementsAsync.isLoading || payersAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (usersAsync.hasError || expensesAsync.hasError || splitsAsync.hasError || 
        tourAsync.hasError || settlementsAsync.hasError || payersAsync.hasError) {
      return const Center(child: Text("Error loading settlement data"));
    }

    final users = usersAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];
    final tourSplits = splitsAsync.value ?? [];
    final tour = tourAsync.value;
    final previousSettlements = settlementsAsync.value ?? [];
    final tourPayers = payersAsync.value ?? [];

    if (tour == null) return const Center(child: Text("Tour not found"));

    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final averageCost = users.isEmpty ? 0.0 : totalCost / users.length;

    final calculator = SettlementCalculator();
    final instructions = calculator.calculate(expenses, tourSplits, tourPayers, users, previousSettlements);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Analysis Summary Section ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionTitle("${config.label} Analysis", config.color),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => FinalReceiptScreen(
                      tourId: tourId,
                    )));
                  },
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: Text("Export ${config.label} Summary", style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: config.color),
                )
              ],
            ),

            Card(
              elevation: 0,
              color: config.color.withOpacity(0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem("Total Cost", "${totalCost.toStringAsFixed(0)} ৳", Icons.account_balance_wallet_outlined, config.color),
                        Container(width: 1, height: 40, color: config.color.withOpacity(0.2)),
                        _buildStatItem("Per Person", "${averageCost.toStringAsFixed(0)} ৳", Icons.person_outline, config.color),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- Logic Explanation Section ---
            _buildSectionTitle("How it's Calculated", config.color),
            InkWell(
               onTap: () => _showAlgorithmExplanation(context, config),
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
                      _buildRuleItem(Icons.auto_awesome, "Greedy Minimization", "We use a smart algorithm that reduces the number of transactions, so most people only have to pay once.", config.color),
                      const Divider(height: 24),
                      _buildRuleItem(Icons.balance, "Equal Distribution", "The total cost is divided equally among all group members.", config.color),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // --- Contribution Summary Section ---
            _buildSectionTitle("Contribution Summary", config.color),
            ...users.map((u) {
              final expensesWithPayerRecords = tourPayers.map((p) => p.expenseId).toSet();
              
              double paidOnExpenses = tourPayers
                  .where((p) => p.userId == u.id)
                  .fold(0.0, (sum, p) => sum + p.amount);
              
              // Add legacy expenses
              for (var e in expenses) {
                if (!expensesWithPayerRecords.contains(e.id) && e.payerId == u.id) {
                  paidOnExpenses += e.amount;
                }
              }

              final share = tourSplits.where((s) => s.userId == u.id).fold(0.0, (sum, s) => sum + s.amount);
              
              // Add settlements (money paid to others increases investment, money received decreases it)
              final paidSettlements = previousSettlements.where((s) => s.fromId == u.id).fold(0.0, (sum, s) => sum + s.amount);
              final receivedSettlements = previousSettlements.where((s) => s.toId == u.id).fold(0.0, (sum, s) => sum + s.amount);
              
              final totalInvested = paidOnExpenses + paidSettlements;
              final netReceived = receivedSettlements;
              final balance = totalInvested - share - netReceived;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade100),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: config.color.withOpacity(0.1),
                    child: Text(u.name[0], style: TextStyle(color: config.color, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Paid: ${paidOnExpenses.toStringAsFixed(0)} ৳ | Share: ${share.toStringAsFixed(0)} ৳", 
                        style: const TextStyle(fontSize: 12)),
                      if (paidSettlements > 0 || receivedSettlements > 0)
                        Text(
                          "${paidSettlements > 0 ? 'Settled: +${paidSettlements.toStringAsFixed(0)} ' : ''}${receivedSettlements > 0 ? 'Received: -${receivedSettlements.toStringAsFixed(0)}' : ''}",
                          style: TextStyle(fontSize: 10, color: config.color.withOpacity(0.7), fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)} ৳",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: balance >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                      Text(
                        balance >= 0 ? "Creditor" : "Debtor",
                        style: TextStyle(fontSize: 10, color: balance >= 0 ? Colors.green : Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 24),

            if (previousSettlements.isNotEmpty) ...[
              _buildSectionTitle("Recent Transactions", config.color),
              ...previousSettlements.reversed.take(3).map((s) => ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                title: Text("${users.firstWhere((u) => u.id == s.fromId).name} paid ${users.firstWhere((u) => u.id == s.toId).name}", style: const TextStyle(fontSize: 12)),
                subtitle: Text(DateFormat('MMM dd').format(s.date), style: const TextStyle(fontSize: 10)),
                trailing: Text("${s.amount.toStringAsFixed(0)} ৳", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onLongPress: () => _confirmDeleteSettlement(context, ref, s),
              )),
              const SizedBox(height: 24),
            ],

            const SizedBox(height: 24),
            _buildSectionTitle("Settlement Plan | লেনদেন গাইড", config.color),

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
              _buildVisualFlow(context, ref, instructions, config),
            ],
            const SizedBox(height: 80),
          ],
        );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRuleItem(IconData icon, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
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

  void _showAlgorithmExplanation(BuildContext context, PurposeConfig config) {
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
            Text("হিসাব নিকাশ কিভাবে হয়? 🧠", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: config.color)),
            const Text("How calculations work", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                   _buildStep(1, "ব্যালেন্স ক্যালকুলেশন", "প্রথমে অ্যাপটি দেখে যে ${config.label.toLowerCase()}-এ কার কত টাকা দেওয়ার কথা ছিল এবং সে বাস্তবে কত টাকা দিয়েছে। (Paid - Share = Balance)", config.color),
                   _buildStep(2, "পাওনাদার ও দেনাদার আলাদা করা", "যাদের ব্যালেন্স পজিটিভ তারা টাকা পাবে (Creditors), আর যাদের নেগেটিভ তারা টাকা দিবে (Debtors)।", config.color),
                   _buildStep(3, "Greedy Flow Minimization", "আমরা একটি স্মার্ট অ্যালগরিদম ব্যবহার করি যা সবচেয়ে বড় দেনাদারকে সবচেয়ে বড় পাওনাদারের সাথে মিলিয়ে দেয়। এর ফলে লেনদেনের সংখ্যা (Number of Transactions) সবচেয়ে কম হয়।", config.color),
                   _buildStep(4, "সহজ সমাধান", "এর উদ্দেশ্য হলো যেন ${config.label.toLowerCase()} শেষে সবাইকে সবার হাতে টাকা দিতে না হয়, বরং মাত্র কয়েকজনের মধ্যে লেনদেন করলেই সবার হিসাব মিলে যায়।", config.color),
                   const SizedBox(height: 24),
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(color: config.color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                     child: Column(
                       children: [
                         Text("উদাহরণ:", style: TextStyle(fontWeight: FontWeight.bold, color: config.color)),
                         const SizedBox(height: 8),
                         const Text("আবির ৫০০৳ পায়, আর সজল ৫০০৳ দিবে। অ্যালগরিদম সজলকে সরাসরি আবিরকে টাকা দিতে বলবে, মাঝখানে অন্য কারো কোনো ঝামেলা থাকবে না।", 
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
                style: FilledButton.styleFrom(backgroundColor: config.color),
                child: const Text("বুঝেছি!"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int no, String title, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 12, backgroundColor: color, child: Text(no.toString(), style: const TextStyle(fontSize: 12, color: Colors.white))),
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

  Widget _buildUserAvatar(String name, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color,
          child: Text(name[0], style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildVisualFlow(BuildContext context, WidgetRef ref, List<SettlementInstruction> instructions, PurposeConfig config) {
    final groupedByPayer = <String, List<SettlementInstruction>>{};
    for (var s in instructions) {
      groupedByPayer.putIfAbsent(s.payerName, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Visual Payment Network | পেমেন্ট গ্রাফ", config.color),
        ...groupedByPayer.entries.map((entry) {
          final payer = entry.key;
          final receivers = entry.value;

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: config.color.withOpacity(0.2), width: 1),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [config.color.withOpacity(0.05), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildUserAvatar(payer, config.color),
                  const SizedBox(width: 12),
                  _buildCustomArrow(config.color),
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
                                child: InkWell(
                                  onTap: () => _markAsPaid(context, ref, r),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${r.amount.toStringAsFixed(0)} ৳",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: config.color,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const Text("Tap to mark as paid", style: TextStyle(fontSize: 9, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_right, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              _buildSmallAvatar(r.receiverName, config.color),
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

  Widget _buildCustomArrow(Color color) {
    return Column(
      children: [
        Container(
          width: 2,
          height: 30,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.2), color],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Icon(Icons.arrow_drop_down, color: color, size: 16),
      ],
    );
  }

  Widget _buildSmallAvatar(String name, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withOpacity(0.2),
          child: Text(name[0], style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _markAsPaid(BuildContext context, WidgetRef ref, SettlementInstruction r) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Payment"),
        content: Text("Did ${r.payerName} really pay ${r.amount.toStringAsFixed(0)} ৳ to ${r.receiverName}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              final settlement = models.Settlement(
                id: const Uuid().v4(),
                tourId: tourId,
                fromId: r.payerId,
                toId: r.receiverId,
                amount: r.amount,
                date: DateTime.now(),
                isSynced: false,
              );
              await database.createSettlement(settlement);
              if (context.mounted) Navigator.pop(context);
              
              // Trigger sync
              ref.read(syncServiceProvider).startSync(r.payerId).catchError((e) => print("Sync failed: $e"));
            }, 
            child: const Text("Yes, Mark as Paid")
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSettlement(BuildContext context, WidgetRef ref, models.Settlement s) {
     showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Transaction?"),
        content: const Text("This will return the debt to the settlement plan."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              await database.deleteSettlement(s.id);
              if (context.mounted) Navigator.pop(context);
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}
