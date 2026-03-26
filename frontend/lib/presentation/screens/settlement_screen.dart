import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart' as models;
import '../../domain/logic/settlement_calculator.dart';
import 'package:frontend/data/providers/app_providers.dart';
import 'final_receipt_screen.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../domain/logic/purpose_config.dart';
import '../widgets/premium_card.dart';

class SettlementScreen extends ConsumerWidget {
  final String tourId;
  const SettlementScreen({super.key, required this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourAsync = ref.watch(singleTourProvider(tourId));
    final tour = tourAsync.value;
    final config = PurposeConfig.getConfig(tour?.purpose);

    final currentUserAsync = ref.watch(currentUserProvider);
    final usersAsync = ref.watch(tourUsersProvider(tourId));
    final expensesAsync = ref.watch(tourExpensesProvider(tourId));
    final splitsAsync = ref.watch(tourSplitsProvider(tourId));
    final settlementsAsync = ref.watch(tourSettlementsProvider(tourId));
    final payersAsync = ref.watch(tourPayersProvider(tourId));
    final membersAsync = ref.watch(tourMembersProvider(tourId));
    final incomesAsync = ref.watch(tourIncomesProvider(tourId));

    if (usersAsync.isLoading || expensesAsync.isLoading || splitsAsync.isLoading || 
        tourAsync.isLoading || settlementsAsync.isLoading || payersAsync.isLoading || membersAsync.isLoading || incomesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (usersAsync.hasError || expensesAsync.hasError || splitsAsync.hasError || 
        tourAsync.hasError || settlementsAsync.hasError || payersAsync.hasError || membersAsync.hasError || incomesAsync.hasError) {
      return const Center(child: Text("Error loading settlement data", style: TextStyle(color: Colors.red)));
    }

    final users = usersAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];
    final tourSplits = splitsAsync.value ?? [];
    final myId = ref.watch(currentUserProvider).value?.id;
    final previousSettlements = (settlementsAsync.value ?? []).toList();
    final tourPayers = payersAsync.value ?? [];
    final tourMembers = membersAsync.value ?? [];
    final incomes = incomesAsync.value ?? [];

    if (tour == null) return const Center(child: Text("Data not found"));

    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final averageCost = users.isEmpty ? 0.0 : totalCost / users.length;

    final mealCounts = { for (var m in tourMembers) m.user.id : m.mealCount };
    final calculator = SettlementCalculator();

    final instructions = calculator.calculate(
      expenses, 
      tourSplits, 
      tourPayers, 
      users, 
      previousSettlements,
      purpose: tour.purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );

    final balanceDetailsMap = calculator.getFullBalances(
      expenses: expenses,
      splits: tourSplits,
      expensePayers: tourPayers,
      users: users,
      previousSettlements: previousSettlements,
      purpose: tour.purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );

    final totalMealCost = expenses.where((e) => e.messCostType == 'meal').fold(0.0, (s, e) => s + e.amount);
    final totalMeals = tourMembers.fold(0.0, (s, m) => s + m.mealCount);
    final mealRate = totalMeals > 0 ? totalMealCost / totalMeals : 0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle("${config.label} Summary", config.color),
            TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => FinalReceiptScreen(tourId: tourId)));
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text("Export Report", style: TextStyle(fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: config.color),
            )
          ],
        ),

        PremiumCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Total Cost", "৳${totalCost.toStringAsFixed(0)}", Icons.account_balance_wallet_rounded, config.color),
                  Container(width: 1, height: 40, color: Colors.black12),
                  if (tour.purpose.toLowerCase() == 'mess')
                    _buildStatItem("Meal Rate", "৳${mealRate.toStringAsFixed(2)}", Icons.restaurant_menu_rounded, config.color)
                  else
                    _buildStatItem("Avg. Share", "৳${averageCost.toStringAsFixed(0)}", Icons.person_rounded, config.color),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        _buildSectionTitle("Individual Balances", config.color),
        ...users.map((u) {
          final details = balanceDetailsMap[u.id];
          if (details == null) return const SizedBox.shrink();

          final balance = details.net;
          final isSettled = balance.abs() < 0.1;

          return PremiumCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: config.color.withOpacity(0.1),
                  child: Text(u.name[0].toUpperCase(), style: TextStyle(color: config.color, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        "Paid: ৳${details.paid.toStringAsFixed(0)} | Share: ৳${details.share.toStringAsFixed(0)}", 
                        style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.7), fontWeight: FontWeight.w600)
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)} ৳",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: isSettled ? Colors.black26 : (balance > 0 ? Colors.green : Colors.redAccent),
                      ),
                    ),
                    Text(
                      isSettled ? "Settled" : (balance > 0 ? "Receivable" : "Payable"),
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                        color: isSettled ? Colors.black26 : (balance > 0 ? Colors.green : Colors.redAccent)
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),

        const SizedBox(height: 32),
        _buildSectionTitle("Settlement Guide", config.color),
        if (instructions.isEmpty)
          PremiumCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(Icons.verified_rounded, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text("Perfectly Settled!", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5)),
                const Text("All accounts are balanced.", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else ...[
          _buildVisualFlow(context, ref, instructions, config),
        ],

        if (previousSettlements.isNotEmpty) ...[
          const SizedBox(height: 32),
          _buildSectionTitle("Recent Payments", config.color),
          ...previousSettlements.reversed.take(5).map((s) {
            final fromUser = users.firstWhere((u) => u.id == s.fromId, orElse: () => models.User(id: '', name: 'Deleted User', phone: '', updatedAt: DateTime.now(), purpose: '', isSynced: false, isMe: false));
            final toUser = users.firstWhere((u) => u.id == s.toId, orElse: () => models.User(id: '', name: 'Deleted User', phone: '', updatedAt: DateTime.now(), purpose: '', isSynced: false, isMe: false));
            
            return PremiumCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                title: Text("${fromUser.name} ➔ ${toUser.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(DateFormat('MMM dd, hh:mm a').format(s.date), style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
                trailing: Text("৳${s.amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                onLongPress: () => _confirmDeleteSettlement(context, ref, s),
              ),
            );
          }),
        ],
        
        const SizedBox(height: 24),
        if (tour.purpose.toLowerCase() == 'mess') 
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => _confirmCloseMonth(context, ref, tour, balanceDetailsMap, users),
              icon: const Icon(Icons.next_plan_rounded),
              label: const Text("Close Month & Carry Balances", style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: config.color,
                side: BorderSide(color: config.color, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title.toUpperCase(), 
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.2)
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.05), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 12),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _confirmCloseMonth(BuildContext context, WidgetRef ref, models.Tour tour, Map<String, UserBalanceDetails> balanceMap, List<models.User> users) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("Close Month session?"),
        content: const Text("This will finalize current month and carry forward balances as primary funds in a new month."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => _closeMonth(context, ref, tour, balanceMap, users), 
            child: const Text("Finalize Now"),
          ),
        ],
      ),
    );
  }

  Future<void> _closeMonth(BuildContext context, WidgetRef ref, models.Tour tour, Map<String, UserBalanceDetails> balanceMap, List<models.User> users) async {
    Navigator.pop(context); // Close dialog
    
    final db = ref.read(databaseProvider);
    final nextMonthId = const Uuid().v4();
    final nextMonthName = "${tour.name} (Next)";
    
    // 1. Create New Tour
    await db.createTour(models.Tour(
      id: nextMonthId,
      name: nextMonthName,
      purpose: tour.purpose,
      createdBy: tour.createdBy,
      startDate: tour.endDate?.add(const Duration(days: 1)) ?? DateTime.now(),
      isSynced: false,
      updatedAt: DateTime.now(),
    ));
    
    // 2. Add Members & Carry Forward Balances
    for (var u in users) {
      await db.into(db.tourMembers).insert(models.TourMember(
        tourId: nextMonthId, 
        userId: u.id, 
        isSynced: false,
        mealCount: 0.0,
        status: 'active',
        role: 'viewer',
      ));
      
      final balance = balanceMap[u.id]?.net ?? 0.0;
      if (balance.abs() > 0.1) {
        await db.createProgramIncome(models.ProgramIncome(
          id: const Uuid().v4(),
          tourId: nextMonthId,
          amount: balance,
          source: 'Balance Brought Forward',
          description: balance > 0 ? 'Surplus from previous session' : 'Due from previous session',
          collectedBy: u.id,
          date: DateTime.now(),
          isSynced: false,
        ));
      }
    }
    
    if (context.mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New session created successfully!")));
       Navigator.pop(context);
    }
  }

  Widget _buildVisualFlow(BuildContext context, WidgetRef ref, List<SettlementInstruction> instructions, PurposeConfig config) {
    final groupedByPayer = <String, List<SettlementInstruction>>{};
    for (var s in instructions) {
      groupedByPayer.putIfAbsent(s.payerName, () => []).add(s);
    }

    return Column(
      children: groupedByPayer.entries.map((entry) {
        final payer = entry.key;
        final receivers = entry.value;

        return PremiumCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: Colors.redAccent.withOpacity(0.1), child: Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.redAccent)),
                  const SizedBox(width: 8),
                  Text(payer, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const Text(" should pay:", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(left: 11, top: 4, bottom: 4),
                child: DottedLine(height: 20),
              ),
              ...receivers.map((r) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 12),
                child: InkWell(
                  onTap: () => _markAsPaid(context, ref, r, config),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: config.color.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: config.color.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Text("৳${r.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: config.color)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.black26),
                        const SizedBox(width: 8),
                        CircleAvatar(radius: 10, backgroundColor: config.color.withOpacity(0.2), child: Text(r.receiverName[0], style: TextStyle(fontSize: 8, color: config.color, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Text(r.receiverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        const Text("PAID?", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              )),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _markAsPaid(BuildContext context, WidgetRef ref, SettlementInstruction r, PurposeConfig config) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Confirm Payment"),
        content: Text("Confirm that ${r.payerName} paid ৳${r.amount.toStringAsFixed(0)} to ${r.receiverName}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
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
              ref.read(syncServiceProvider).startSync(r.payerId).catchError((e) => debugPrint("Sync failed: $e"));
            }, 
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSettlement(BuildContext context, WidgetRef ref, models.Settlement s) {
     showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Undo Transaction?"),
        content: const Text("This will remove this payment record and revert the balance."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              await database.deleteSettlement(s.id);
              if (context.mounted) Navigator.pop(context);
            }, 
            child: const Text("Undo", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }
}

class DottedLine extends StatelessWidget {
  final double height;
  const DottedLine({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
