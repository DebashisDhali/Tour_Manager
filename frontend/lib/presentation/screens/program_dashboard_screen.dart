import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import '../../data/local/app_database.dart';
import 'package:frontend/data/providers/app_providers.dart';
import '../widgets/add_income_dialog.dart';
import '../widgets/allocate_fund_dialog.dart';

class ProgramDashboardScreen extends ConsumerStatefulWidget {
  final String tourId;
  final String tourName;

  const ProgramDashboardScreen({super.key, required this.tourId, required this.tourName});

  @override
  ConsumerState<ProgramDashboardScreen> createState() => _ProgramDashboardScreenState();
}

class _ProgramDashboardScreenState extends ConsumerState<ProgramDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Program Finance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.tourName, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Overview"),
            Tab(text: "Incomes"),
            Tab(text: "Allocations"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildIncomesTab(),
          _buildAllocationsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 1) {
            _showAddIncomeDialog();
          } else if (_tabController.index == 2) {
            _showAllocateFundDialog();
          } else {
             // In overview, ask what to do
             _showAddOptionsSheet();
          }
        },
        label: Text(_tabController.index == 1 ? "Add Income" : (_tabController.index == 2 ? "Allocate" : "Manage")),
        icon: Icon(_tabController.index == 1 ? Icons.add_card : (_tabController.index == 2 ? Icons.send : Icons.grid_view)),
      ),
    );
  }

  void _showAddOptionsSheet() {
    showModalBottomSheet(
      context: context, 
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_card),
            title: const Text("Add Collected Fund"),
            onTap: () { Navigator.pop(context); _showAddIncomeDialog(); },
          ),
          ListTile(
            leading: const Icon(Icons.send),
            title: const Text("Allocate Fund to Member"),
            onTap: () { Navigator.pop(context); _showAllocateFundDialog(); },
          ),
        ],
      )
    );
  }

  void _showAddIncomeDialog() {
    showDialog(context: context, builder: (_) => AddIncomeDialog(tourId: widget.tourId));
  }

  void _showAllocateFundDialog() {
    showDialog(context: context, builder: (_) => AllocateFundDialog(tourId: widget.tourId));
  }

  Widget _buildOverviewTab() {
    final db = ref.watch(databaseProvider);
    
    // Construct a stream for users to avoid FutureBuilder flickering and repeated calls
    final usersStream = (db.select(db.users).join([
      drift.innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id))
    ])..where(db.tourMembers.tourId.equals(widget.tourId)))
    .map((row) => row.readTable(db.users))
    .watch();

    return StreamBuilder<List<ProgramIncome>>(
      stream: db.programIncomes.select().watch(), 
      builder: (context, incomeSnap) {
        final incomes = (incomeSnap.data ?? []).where((i) => i.tourId == widget.tourId).toList();
        final totalCollected = incomes.fold(0.0, (sum, item) => sum + item.amount);

        return StreamBuilder<List<Expense>>(
          stream: db.expenses.select().watch(),
          builder: (context, expenseSnap) {
            final expenses = (expenseSnap.data ?? []).where((e) => e.tourId == widget.tourId).toList();
            final totalSpent = expenses.fold(0.0, (sum, item) => sum + item.amount);

            return StreamBuilder<List<Settlement>>(
              stream: db.settlements.select().watch(),
              builder: (context, settlementSnap) {
                final settlements = (settlementSnap.data ?? []).where((s) => s.tourId == widget.tourId).toList();
                
                final currentBalance = totalCollected - totalSpent; 

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard("Total Collected", totalCollected, Colors.teal),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildSummaryCard("Total Spent", totalSpent, Colors.orange)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummaryCard("Balance", currentBalance, currentBalance >= 0 ? Colors.green : Colors.red)),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      const Text("Net Financial Status", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text(
                        "Who holds the money vs. Who spent from pocket",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      
                      // Use StreamBuilder for users instead of FutureBuilder
                      StreamBuilder<List<User>>(
                        stream: usersStream,
                        builder: (context, userSnap) {
                          if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
                          
                          final users = userSnap.data!;
                          final userBalances = <User, double>{};

                          for (final user in users) {
                            final collected = incomes.where((i) => i.collectedBy == user.id).fold(0.0, (sum, i) => sum + i.amount);
                            final received = settlements.where((s) => s.toId == user.id).fold(0.0, (sum, s) => sum + s.amount);
                            final given = settlements.where((s) => s.fromId == user.id).fold(0.0, (sum, s) => sum + s.amount);
                            final spent = expenses.where((e) => e.payerId == user.id).fold(0.0, (sum, e) => sum + e.amount);
                            
                            userBalances[user] = collected + received - given - spent;
                          }

                          // Sort: Most positive (Cash in hand) first, then most negative (Reimbursable)
                          users.sort((a, b) => (userBalances[b] ?? 0).compareTo(userBalances[a] ?? 0));

                          return Column(
                            children: users.map((user) {
                              final balance = userBalances[user] ?? 0.0;
                              if (balance.abs() < 1) return const SizedBox.shrink(); // Hide nearly zero balances

                              final isPositive = balance > 0;
                              
                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  side: BorderSide(color: isPositive ? Colors.green.withValues(alpha: 0.5) : Colors.orange.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(12)
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isPositive ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                    child: Text(
                                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                      style: TextStyle(color: isPositive ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(isPositive 
                                    ? "Has Program Money" 
                                    : "Spent Personal Money (Needs Refund)"),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isPositive ? Colors.green : Colors.orange,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      "${isPositive ? 'Cash In Hand' : 'Claimable'}: ৳${balance.abs().toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 12
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        }
                      )
                    ],
                  ),
                );
              }
            );
          }
        );
      },
    );
  }
  
  Widget _buildSummaryCard(String title, double amount, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            NumberFormat.currency(symbol: '৳', decimalDigits: 0).format(amount),
            style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomesTab() {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<ProgramIncome>>(
      stream: (db.select(db.programIncomes)..where((t) => t.tourId.equals(widget.tourId))).watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final incomes = snapshot.data!;
        
        if (incomes.isEmpty) {
          return const Center(child: Text("No funds collected yet."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: incomes.length,
          itemBuilder: (context, index) {
            final income = incomes[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.greenAccent, child: Icon(Icons.arrow_downward, color: Colors.green)),
                title: Text(income.source),
                subtitle: FutureBuilder<User?>(
                  future: db.getUserById(income.collectedBy),
                  builder: (context, snap) => Text("Collected by: ${snap.data?.name ?? 'Unknown'}\n${DateFormat.yMMMd().format(income.date)}"),
                ),
                trailing: Text(
                  "+৳${income.amount.toStringAsFixed(0)}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16),
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAllocationsTab() {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<Settlement>>(
      stream: (db.select(db.settlements)..where((t) => t.tourId.equals(widget.tourId))).watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final settlements = snapshot.data!;
        
        if (settlements.isEmpty) {
          return const Center(child: Text("No funds allocated/distributed yet."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: settlements.length,
          itemBuilder: (context, index) {
            final s = settlements[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.swap_horiz, color: Colors.white)),
                title: FutureBuilder<User?>(
                  future: db.getUserById(s.toId),
                  builder: (context, snap) => Text("To: ${snap.data?.name ?? 'Unknown'}"),
                ),
                subtitle: FutureBuilder<User?>(
                  future: db.getUserById(s.fromId),
                  builder: (context, snap) => Text("From: ${snap.data?.name ?? 'Unknown'}\n${DateFormat.yMMMd().format(s.date)}"),
                ),
                trailing: Text(
                  "৳${s.amount.toStringAsFixed(0)}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

