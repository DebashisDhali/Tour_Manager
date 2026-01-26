import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:math';
import 'user_profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_providers.dart';
import '../widgets/add_member_dialog.dart';
import 'add_expense_screen.dart';
import 'settlement_screen.dart';
import 'package:intl/intl.dart';
import '../../data/local/app_database.dart';
import '../../main.dart';

class TourDetailsScreen extends ConsumerStatefulWidget {
  final String tourId;
  final String tourName;

  const TourDetailsScreen({super.key, required this.tourId, required this.tourName});

  @override
  ConsumerState<TourDetailsScreen> createState() => _TourDetailsScreenState();
}

class _TourDetailsScreenState extends ConsumerState<TourDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Consumer(
            builder: (context, ref, child) {
              final tourAsync = ref.watch(singleTourProvider(widget.tourId));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.tourName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  tourAsync.when(
                    data: (tour) => Text(
                      tour.startDate == null 
                        ? 'Manage Expenses & Friends' 
                        : '${DateFormat('MMM dd').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8)),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (e, s) => const Text('Error loading date', style: TextStyle(fontSize: 10)),
                  ),
                ],
              );
            },
          ),
          actions: [
            Consumer(
              builder: (context, ref, child) {
                final tourAsync = ref.watch(singleTourProvider(widget.tourId));
                return tourAsync.when(
                  data: (tour) {
                    if (tour.inviteCode != null) {
                      return IconButton(
                        icon: const Icon(Icons.share_outlined),
                        onPressed: () => _showInviteCode(context, tour.inviteCode!),
                        tooltip: 'Invite Friends',
                      );
                    } else {
                      return IconButton(
                        icon: const Icon(Icons.vpn_key_outlined),
                        onPressed: () => _generateAndShowCode(context, tour),
                        tooltip: 'Generate Invite Code',
                      );
                    }
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (e, s) => const SizedBox.shrink(),
                );
              },
            ),
          ],
          bottom: const TabBar(

            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'Expenses'),
              Tab(icon: Icon(Icons.people), text: 'Members'),
              Tab(icon: Icon(Icons.analytics), text: 'Summary'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildExpensesTab(),
            _buildMembersTab(),
            _buildSummaryTab(),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            final tabIndex = DefaultTabController.of(context).index;
            return FloatingActionButton.extended(
              onPressed: () => _handleFabPress(context),
              icon: const Icon(Icons.add),
              label: Text(tabIndex == 1 ? "Add Member" : "Add Expense"),
            );
          },
        ),
      ),
    );
  }

  void _handleFabPress(BuildContext context) {
    final tabIndex = DefaultTabController.of(context).index;
    if (tabIndex == 1) {
      showDialog(
        context: context,
        builder: (_) => AddMemberDialog(tourId: widget.tourId),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId)),
      );
    }
  }

  void _generateAndShowCode(BuildContext context, Tour tour) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();
    
    final db = ref.read(databaseProvider);
    await (db.update(db.tours)..where((t) => t.id.equals(tour.id))).write(ToursCompanion(
      inviteCode: Value(code),
      isSynced: const Value(false),
    ));
    
    if (context.mounted) {
      _showInviteCode(context, code);
    }
  }

  void _showInviteCode(BuildContext context, String code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Friends'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with your friends. They can join the tour from the home screen.'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Text(
                code,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.teal),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              // In a real app, use share_plus package
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied to clipboard!')));
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy & Share'),
          ),
        ],
      ),
    );
  }

  Widget _buildExpensesTab() {
    // ... same as before
    final expensesAsync = ref.watch(expensesProvider(widget.tourId));

    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_accounts_outlined, size: 60, color: Colors.teal.shade200),
                const SizedBox(height: 16),
                const Text('No expenses yet. Add one to start tracking!'),
              ],
            ),
          );
        }

        double total = expenses.fold(0, (sum, e) => sum + e.expense.amount);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.teal.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Spent:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text("${total.toStringAsFixed(0)} ৳", 
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: expenses.length,
                itemBuilder: (context, index) {
                  final item = expenses[index];
                  final exp = item.expense;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: _getCategoryColor(exp.category).withOpacity(0.1),
                        child: Icon(_getCategoryIcon(exp.category), color: _getCategoryColor(exp.category)),
                      ),
                      title: Text(exp.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Paid by: ${item.payer.name}"),
                          Text(DateFormat('MMM dd, hh:mm a').format(exp.createdAt), style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      trailing: Text("${exp.amount.toStringAsFixed(0)} ৳", 
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
    );
  }

  Widget _buildMembersTab() {
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));
    final currentUserAsync = ref.watch(currentUserProvider);

    return Column(
      children: [
        Expanded(
          child: membersAsync.when(
            data: (members) {
              return tourAsync.when(
                data: (tour) {
                  return currentUserAsync.when(
                    data: (me) {
                      final isCreator = me?.id == tour.createdBy;

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final user = member.user;
                          final hasLeft = member.leftAt != null;
                          final isMe = me?.id == user.id;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: hasLeft ? Colors.red.shade100 : Colors.grey.shade200),
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)));
                              },
                              leading: CircleAvatar(
                                backgroundColor: hasLeft ? Colors.grey.shade100 : Colors.teal.shade50,
                                backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                                child: user.avatarUrl == null ? Text(user.name[0], style: TextStyle(color: hasLeft ? Colors.grey : Colors.teal, fontWeight: FontWeight.bold)) : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(isMe ? "${user.name} (You)" : user.name, style: TextStyle(fontWeight: FontWeight.bold, color: hasLeft ? Colors.grey : Colors.black))),
                                  if (hasLeft)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                                      child: const Text("Left", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              subtitle: Text(hasLeft ? "Departed on ${DateFormat('MMM dd, HH:mm').format(member.leftAt!)}" : (user.phone ?? "No phone number"), style: const TextStyle(fontSize: 12)),
                              trailing: hasLeft 
                                ? null 
                                : PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'leave') {
                                        _showLeaveConfirmation(user, isRemoval: !isMe);
                                      }
                                    },
                                    itemBuilder: (context) {
                                      final items = <PopupMenuEntry<String>>[];
                                      if (isMe && !isCreator) {
                                        items.add(const PopupMenuItem(value: 'leave', child: Text("Leave Tour")));
                                      } else if (isCreator && !isMe) {
                                        items.add(const PopupMenuItem(value: 'leave', child: Text("Remove Member")));
                                      }
                                      return items;
                                    },
                                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                                  ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, s) => Center(child: Text("Error: $e")),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text("Error: $e")),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text("Error: $e")),
          ),
        ),
      ],
    );
  }

  void _showLeaveConfirmation(User user, {required bool isRemoval}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRemoval ? "Remove Member" : "Leave Tour"),
        content: Text(isRemoval 
          ? "Are you sure you want to remove ${user.name} from this tour? They will be excluded from all future expenses."
          : "Are you sure you want to leave this tour? You will no longer be included in any upcoming expenses."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              await ref.read(databaseProvider).markMemberAsLeft(widget.tourId, user.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isRemoval ? "${user.name} has been removed." : "You have left the tour.")));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isRemoval ? "Remove" : "Leave"),
          ),
        ],
      ),
    );
  }

  

  Widget _buildSummaryTab() {
    return SettlementScreen(tourId: widget.tourId);
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food': return Icons.restaurant;
      case 'transport': return Icons.directions_bus;
      case 'hotel': return Icons.hotel;
      case 'shopping': return Icons.shopping_bag;
      default: return Icons.more_horiz;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food': return Colors.orange;
      case 'transport': return Colors.blue;
      case 'hotel': return Colors.purple;
      case 'shopping': return Colors.pink;
      default: return Colors.grey;
    }
  }
}

