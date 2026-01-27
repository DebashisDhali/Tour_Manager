import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:math';
import 'user_profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_providers.dart';
import '../widgets/add_member_dialog.dart';
import 'add_expense_screen.dart';
import 'settlement_screen.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/local/app_database.dart';
import '../../main.dart';
import '../../domain/logic/purpose_config.dart';

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
                  Text(widget.tourName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  tourAsync.when(
                    data: (tour) => Consumer(
                      builder: (context, ref, child) {
                         final creatorAsync = ref.watch(singleUserProvider(tour.createdBy));
                         return Row(
                           children: [
                             Icon(Icons.person_pin_circle_outlined, size: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5)),
                             const SizedBox(width: 4),
                             creatorAsync.when(
                               data: (user) => Text(
                                 "Created by ${user?.name ?? 'Unknown'}",
                                 style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7)),
                               ),
                               loading: () => const Text("Loading...", style: TextStyle(fontSize: 10)),
                               error: (_, __) => const Text("Error", style: TextStyle(fontSize: 10)),
                             ),
                             const SizedBox(width: 8),
                             Icon(Icons.calendar_today_outlined, size: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5)),
                             const SizedBox(width: 4),
                             Text(
                               tour.startDate == null 
                                 ? 'Ongoing' 
                                 : '${DateFormat('MMM dd').format(tour.startDate!)} - ${DateFormat('MMM dd').format(tour.endDate ?? tour.startDate!)}',
                               style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7)),
                             ),
                           ],
                         );
                      },
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (e, s) => const Text('Error loading details', style: TextStyle(fontSize: 10)),
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
            final userAsync = ref.watch(currentUserProvider);
            final config = PurposeConfig.getConfig(userAsync.value?.purpose);
            
            return FloatingActionButton.extended(
              onPressed: () => _handleFabPress(context),
              icon: const Icon(Icons.add),
              label: Text(tabIndex == 1 ? "Add Member" : "Add Expense"),
              backgroundColor: config.color,
              foregroundColor: Colors.white,
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
    final userAsync = ref.read(currentUserProvider);
    final config = PurposeConfig.getConfig(userAsync.value?.purpose);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Members'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share this code with others. They can join the ${config.label.toLowerCase()} from the home screen.'),
            const SizedBox(height: 20),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 2)),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: config.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: config.color.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      code,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: config.color),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.copy, size: 20, color: config.color.withOpacity(0.5)),
                  ],
                ),
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
              final text = "Join my ${config.label.toLowerCase()} on Manager App! Code: $code\n\nDownload the app to manage expenses together.";
              Share.share(text);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share Code'),
            style: FilledButton.styleFrom(backgroundColor: config.color),
          ),
        ],
      ),
    );
  }

  Widget _buildExpensesTab() {
    final expensesAsync = ref.watch(expensesProvider(widget.tourId));
    final userAsync = ref.watch(currentUserProvider);
    final config = PurposeConfig.getConfig(userAsync.value?.purpose);

    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_accounts_outlined, size: 60, color: config.color.withOpacity(0.3)),
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
              color: config.color.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Spent:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text("${total.toStringAsFixed(0)} ৳", 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: config.color)),
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
                          Text("Paid by: ${item.payer?.name ?? 'Combined'}"),
                          Text(DateFormat('MMM dd, hh:mm a').format(exp.createdAt), style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("${exp.amount.toStringAsFixed(0)} ৳", 
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'edit') {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId, initialExpense: exp)));
                              } else if (val == 'delete') {
                                _showDeleteDialog(context, exp);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'), dense: true)),
                              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), dense: true)),
                            ],
                          ),
                        ],
                      ),
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
    final config = PurposeConfig.getConfig(currentUserAsync.value?.purpose);

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
                                backgroundColor: hasLeft ? Colors.grey.shade100 : config.color.withOpacity(0.1),
                                backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                                child: user.avatarUrl == null ? Text(user.name[0], style: TextStyle(color: hasLeft ? Colors.grey : config.color, fontWeight: FontWeight.bold)) : null,
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
                                        items.add(PopupMenuItem(value: 'leave', child: Text("Leave ${config.label}")));
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
    final userAsync = ref.read(currentUserProvider);
    final config = PurposeConfig.getConfig(userAsync.value?.purpose);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRemoval ? "Remove Member" : "Leave ${config.label}"),
        content: Text(isRemoval 
          ? "Are you sure you want to remove ${user.name} from this ${config.label.toLowerCase()}? They will be excluded from all future expenses."
          : "Are you sure you want to leave this ${config.label.toLowerCase()}? You will no longer be included in any upcoming expenses."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              await ref.read(databaseProvider).markMemberAsLeft(widget.tourId, user.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isRemoval ? "${user.name} has been removed." : "You have left the ${config.label.toLowerCase()}.")) );
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

  void _showDeleteDialog(BuildContext context, Expense exp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Expense?"),
        content: Text("Are you sure you want to delete '${exp.title}'? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final db = ref.read(databaseProvider);
              await db.deleteExpenseWithDetails(exp.id);
              if (context.mounted) Navigator.pop(context);
              // Background Sync (Implementation needed for deletes in SyncService)
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}

