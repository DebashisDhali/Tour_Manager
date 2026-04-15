import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' as drift;
import 'dart:math';
import 'user_profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/data/providers/app_providers.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/add_income_dialog.dart';
import '../widgets/allocate_fund_dialog.dart';
import 'add_expense_screen.dart';
import 'settlement_screen.dart';
import 'final_receipt_screen.dart';
import 'meal_entry_screen.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/local/app_database.dart';
import '../../domain/logic/purpose_config.dart';
import 'program_dashboard_screen.dart';
import 'ai_coach_screen.dart';
import '../widgets/premium_card.dart';

class TourDetailsScreen extends ConsumerStatefulWidget {
  final String tourId;
  final String tourName;
  /// When set, opens directly to the Expenses tab with this member pre-filtered.
  final String? initialFilterMemberId;

  const TourDetailsScreen({
    super.key,
    required this.tourId,
    required this.tourName,
    this.initialFilterMemberId,
  });

  @override
  ConsumerState<TourDetailsScreen> createState() => _TourDetailsScreenState();
}

class _TourDetailsScreenState extends ConsumerState<TourDetailsScreen> with TickerProviderStateMixin {
  String? _selectedFilterMemberId;
  TabController? _tabController;
  int _tabLength = 3;
  bool _isProgram = false;

  @override
  void initState() {
    super.initState();
    // Pre-select a member filter if provided (navigated from summary screen)
    _selectedFilterMemberId = widget.initialFilterMemberId;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _initTabController(Tour tour) {
    final String p = tour.purpose.toLowerCase();
    final bool isProg = p == 'event' || p == 'business' || p == 'project';
    final bool isMess = p == 'mess';
    final int newLength = isProg ? 5 : (isMess ? 4 : 3);
    
    if (_tabController == null || _tabLength != newLength) {
      _tabController?.dispose();
      _tabLength = newLength;
      _isProgram = isProg;
      // If opened from member summary, jump to expenses tab directly
      final int startIndex = widget.initialFilterMemberId != null
          ? (isProg ? 2 : 0) // expenses tab index
          : 0;
      _tabController = TabController(length: _tabLength, vsync: this, initialIndex: startIndex);
      _tabController!.addListener(() {
        if (mounted) setState(() {}); // Rebuild for FAB updates
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));

    return tourAsync.when(
      data: (tour) {
        if (tour == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Tour Deleted")),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.delete_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("This tour has been deleted."),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Back to List"),
                  ),
                ],
              ),
            ),
          );
        }
        
        _initTabController(tour);
        final config = PurposeConfig.getConfig(tour.purpose);

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: true,
            backgroundColor: config.color,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: Container(
              decoration: BoxDecoration(gradient: config.gradient),
              child: Opacity(
                opacity: 0.1,
                child: CustomPaint(painter: _GridPainter(Colors.white)),
              ),
            ),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(tour.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.8)),
                const SizedBox(height: 2),
                Text(
                  tour.startDate == null 
                    ? 'Ongoing Tracker' 
                    : '${DateFormat('MMM dd').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}',
                  style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.auto_awesome, size: 22, color: Colors.amberAccent),
                tooltip: 'AI Insights',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AiCoachScreen(tourId: tour.id, tourName: tour.name),
                  ));
                },
              ),
              if (tour.inviteCode != null)
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 22),
                  onPressed: () => _showInviteCode(context, tour.inviteCode!, tour.purpose),
                  tooltip: 'Invite ${config.memberLabel}',
                )
              else
                IconButton(
                  icon: const Icon(Icons.vpn_key_rounded, size: 22),
                  onPressed: () => _generateAndShowCode(context, tour),
                  tooltip: 'Generate Invite Code',
                ),
              if (ref.watch(currentUserProvider).value?.id == tour.createdBy)
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (val) {
                    if (val == 'delete_tour') {
                      _showDeleteTourConfirmation(context, tour);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete_tour',
                      child: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20), const SizedBox(width: 12), Text('Delete ${config.label}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
                    ),
                  ],
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: _isProgram || (tour.purpose.toLowerCase() == 'mess'),
                  indicator: const UnderlineTabIndicator(
                    borderSide: BorderSide(width: 3.0, color: Colors.white),
                    insets: EdgeInsets.symmetric(horizontal: 16.0),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.2),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  tabs: _isProgram 
                    ? [
                        const Tab(text: 'DASHBOARD'),
                        const Tab(text: 'INCOME'),
                        const Tab(text: 'EXPENSES'),
                        const Tab(text: 'TEAM'),
                        const Tab(text: 'BANK'),
                      ]
                    : [
                        Tab(text: config.expenseListLabel.toUpperCase()),
                        Tab(text: config.memberLabel.toUpperCase()),
                        if (tour.purpose.toLowerCase() == 'mess') const Tab(text: 'MEALS'),
                        const Tab(text: 'SUMMARY'),
                      ],
                ),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: _isProgram
              ? [
                  _buildProgramOverviewTab(tour),
                  _buildIncomesTab(tour),
                  _buildExpensesTab(tour),
                  _buildMembersTab(tour),
                  _buildAllocationsTab(tour),
                ]
              : [
                  _buildExpensesTab(tour),
                  _buildMembersTab(tour),
                  if (tour.purpose.toLowerCase() == 'mess') _buildMealsTab(tour),
                  _buildSummaryTab(),
                ],
          ),
          floatingActionButton: _buildFab(tour),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(body: Center(child: Text("Error: $e"))),
    );
  }

  Widget? _buildFab(Tour tour) {
    final int index = _tabController?.index ?? 0;
    final config = PurposeConfig.getConfig(tour.purpose);

    IconData icon = Icons.add;
    String label = "Add Expense";
    VoidCallback? action;

    if (_isProgram) {
      switch (index) {
        case 0: // Overview
          return FloatingActionButton(
            onPressed: () => _showAddOptionsSheet(tour),
            backgroundColor: config.color,
            child: const Icon(Icons.grid_view, color: Colors.white),
          );
        case 1: // Incomes
          icon = Icons.add_card;
          label = "Add Income";
          action = () => showDialog(context: context, builder: (_) => AddIncomeDialog(tourId: widget.tourId));
          break;
        case 2: // Expenses
          icon = Icons.add;
          label = "Add Expense";
          action = () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId)));
          break;
        case 3: // Members
          icon = Icons.person_add;
          label = "Add ${config.memberLabel}";
          action = () => showDialog(context: context, builder: (_) => AddMemberDialog(tourId: widget.tourId));
          break;
        case 4: // Allocations
          icon = Icons.send;
          label = "Allocate";
          action = () => showDialog(context: context, builder: (_) => AllocateFundDialog(tourId: widget.tourId));
          break;
      }
    } else {
      switch (index) {
        case 0: // Expenses
          icon = Icons.add;
          label = config.addExpenseLabel;
          action = () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId)));
          break;
        case 1: // Members
          icon = Icons.person_add;
          label = "Add ${config.memberLabel}";
          action = () => showDialog(context: context, builder: (_) => AddMemberDialog(tourId: widget.tourId));
          break;
        case 2: // Meals or Summary
           if (tour.purpose.toLowerCase() == 'mess') {
             icon = Icons.restaurant;
             label = "Daily Meals";
             action = () => Navigator.push(context, MaterialPageRoute(builder: (_) => MealEntryScreen(tourId: widget.tourId)));
             break;
           }
           return null;
        default:
          return null;
      }
    }

    return FloatingActionButton.extended(
      onPressed: action,
      icon: Icon(icon),
      label: Text(action == null ? "" : label),
      backgroundColor: config.color,
      foregroundColor: Colors.white,
    );
  }

  void _showAddOptionsSheet(Tour tour) {
    final config = PurposeConfig.getConfig(tour.purpose);
    showModalBottomSheet(
      context: context, 
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.add_card, color: config.color),
            title: const Text("Add Collected Fund"),
            onTap: () { Navigator.pop(context); showDialog(context: context, builder: (_) => AddIncomeDialog(tourId: widget.tourId)); },
          ),
          ListTile(
            leading: Icon(Icons.add, color: config.color),
            title: const Text("Add Expense"),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId))); },
          ),
          ListTile(
            leading: Icon(Icons.send, color: config.color),
            title: const Text("Allocate Fund to Member"),
            onTap: () { Navigator.pop(context); showDialog(context: context, builder: (_) => AllocateFundDialog(tourId: widget.tourId)); },
          ),
        ],
      )
    );
  }

  void _generateAndShowCode(BuildContext context, Tour tour) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();
    
    final db = ref.read(databaseProvider);
    await (db.update(db.tours)..where((t) => t.id.equals(tour.id))).write(ToursCompanion(
      inviteCode: drift.Value(code),
      isSynced: const drift.Value(false),
    ));
    
    if (context.mounted) {
      _showInviteCode(context, code, tour.purpose);
    }
  }

  void _showInviteCode(BuildContext context, String code, String? purpose) {
    final config = PurposeConfig.getConfig(purpose);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invite ${config.memberLabel}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share this code with others. They can join from the home screen.'),
            const SizedBox(height: 20),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied!')),
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
                    Text(code, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: config.color)),
                    const SizedBox(width: 8),
                    Icon(Icons.copy, size: 20, color: config.color.withOpacity(0.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              final text = "Join my ${config.label.toLowerCase()}! Code: $code";
              Share.share(text);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
            style: FilledButton.styleFrom(backgroundColor: config.color),
          ),
        ],
      ),
    );
  }

  Widget _buildExpensesTab(Tour tour) {
    final expensesAsync = ref.watch(expensesProvider(widget.tourId));
    final allPayersAsync = ref.watch(tourPayersProvider(widget.tourId));
    final allUsersAsync = ref.watch(tourUsersProvider(widget.tourId));
    final config = PurposeConfig.getConfig(tour.purpose);

    return expensesAsync.when(
      data: (allExpenses) {
        final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
        final allPayers = allPayersAsync.value ?? [];
        final filteredExpenses = _selectedFilterMemberId == null 
          ? allExpenses 
          : allExpenses.where((e) {
              if (e.expense.payerId == _selectedFilterMemberId) return true;
              return allPayers.any((p) => p.expenseId == e.expense.id && p.userId == _selectedFilterMemberId);
            }).toList();

        if (allExpenses.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 60, color: config.color.withOpacity(0.3)),
                const SizedBox(height: 16),
                const Text('No expenses yet.'),
              ],
            ),
          );
        }

        double total = 0;
        if (_selectedFilterMemberId == null) {
          total = allExpenses.fold(0.0, (sum, e) => sum + e.expense.amount);
        } else {
          final expensesWithPayerRecords = allPayers.map((p) => p.expenseId).toSet();
          total = allPayers
            .where((p) => p.userId == _selectedFilterMemberId)
            .fold(0.0, (sum, p) => sum + p.amount);

          for (var e in allExpenses) {
            if (!expensesWithPayerRecords.contains(e.expense.id) && e.expense.payerId == _selectedFilterMemberId) {
              total += e.expense.amount;
            }
          }
        }

        return Column(
          children: [
            membersAsync.when(
              data: (members) => Container(
                height: 60,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    ChoiceChip(
                      label: const Text("All"),
                      selected: _selectedFilterMemberId == null,
                      onSelected: (_) => setState(() => _selectedFilterMemberId = null),
                      selectedColor: config.color,
                      labelStyle: TextStyle(color: _selectedFilterMemberId == null ? Colors.white : Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(width: 8),
                    ...members.map((m) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(m.user.name),
                        selected: _selectedFilterMemberId == m.user.id,
                        onSelected: (s) => setState(() => _selectedFilterMemberId = s ? m.user.id : null),
                        selectedColor: config.color,
                        labelStyle: TextStyle(color: _selectedFilterMemberId == m.user.id ? Colors.white : Theme.of(context).colorScheme.onSurface),
                      ),
                    )),
                  ],
                ),
              ),
              loading: () => const SizedBox(height: 60),
              error: (_, __) => const SizedBox.shrink(),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: config.color.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Spent:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("৳${total.toStringAsFixed(0)}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: config.color)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: filteredExpenses.length,
                itemBuilder: (context, index) {
                  final item = filteredExpenses[index];
                  final exp = item.expense;

                  // Calculate display payer name(s)
                  String payerText = item.payer?.name ?? 'Combined';
                  if (allPayersAsync.hasValue && allUsersAsync.hasValue && allPayersAsync.value != null && allUsersAsync.value != null) {
                    final expPayers = allPayersAsync.value!.where((p) => p.expenseId == exp.id).toList();
                    if (expPayers.length > 1) {
                      final names = expPayers.map((p) {
                         try {
                           return allUsersAsync.value!.firstWhere((u) => u.id == p.userId).name;
                         } catch (e) {
                           return "User";
                         }
                      }).toList();
                      
                      if (names.length == 2) {
                        payerText = names.join(" & ");
                      } else if (names.isNotEmpty) {
                        payerText = "${names.first} + ${names.length - 1} others";
                      }
                    }
                  }

                  return PremiumCard(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _getCategoryColor(exp.category).withOpacity(0.1),
                          child: Icon(_getCategoryIcon(exp.category), color: _getCategoryColor(exp.category), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(exp.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: -0.2)),
                              const SizedBox(height: 2),
                              Text(
                                "Paid by: $payerText • ${DateFormat('MMM dd, hh:mm a').format(exp.createdAt)}", 
                                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)
                              ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "৳${(() {
                                if (_selectedFilterMemberId == null) return exp.amount;
                                final userPaid = allPayers.where((p) => p.expenseId == exp.id && p.userId == _selectedFilterMemberId);
                                if (userPaid.isNotEmpty) return userPaid.fold(0.0, (sum, p) => sum + p.amount);
                                return exp.payerId == _selectedFilterMemberId ? exp.amount : 0.0;
                              })().toStringAsFixed(0)}", 
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.redAccent)
                            ),
                            if (_selectedFilterMemberId != null) 
                              Text("of ৳${exp.amount.toStringAsFixed(0)}", style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3))),
                          ],
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          onSelected: (val) {
                            if (val == 'edit') Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId, initialExpense: exp)));
                            if (val == 'delete') _showDeleteDialog(context, exp);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(fontSize: 13))),
                            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 13))),
                          ],
                        ),
                      ],
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

  Widget _buildJoinRequests(Tour tour) {
    final me = ref.watch(currentUserProvider).value;
    if (me?.id != tour.createdBy) return const SizedBox.shrink();

    final db = ref.read(databaseProvider);
    return StreamBuilder<List<JoinRequest>>(
      stream: (db.select(db.joinRequests)..where((t) => t.tourId.equals(widget.tourId) & t.status.equals('pending'))).watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final requests = snapshot.data!;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.person_add_alt_1_rounded, size: 20, color: Colors.orange),
                  SizedBox(width: 12),
                  Text("Join Requests", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              ...requests.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(r.userName[0])),
                title: Text(r.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () async {
                        try {
                          await ref.read(syncServiceProvider).handleJoinRequest(r.id, 'approved');
                          await (db.update(db.joinRequests)..where((t) => t.id.equals(r.id))).write(const JoinRequestsCompanion(status: drift.Value('approved')));
                          await ref.read(syncServiceProvider).startSync(me!.id);
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () async {
                        try {
                          await ref.read(syncServiceProvider).handleJoinRequest(r.id, 'rejected');
                          await (db.update(db.joinRequests)..where((t) => t.id.equals(r.id))).write(const JoinRequestsCompanion(status: drift.Value('rejected')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      },
                    ),
                  ],
                ),
              )).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMembersTab(Tour tour) {
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    final config = PurposeConfig.getConfig(tour.purpose);
    final me = ref.watch(currentUserProvider).value;

    return membersAsync.when(
      data: (members) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: config.color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: config.color.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: config.color, size: 20),
                const SizedBox(width: 12),
                const Expanded(child: Text("Invite others via shared code to manage costs together.", style: TextStyle(fontSize: 12))),
                TextButton(onPressed: _showMemberSystemInfo, child: const Text("How it works?", style: TextStyle(fontSize: 11))),
              ],
            ),
          ),
          _buildJoinRequests(tour),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: members.length,
              itemBuilder: (context, index) {
          final m = members[index];
          final isMe = me?.id == m.user.id;
          final isRemoved = m.status.toLowerCase().trim() == 'removed';
          
            final isAdmin = me?.id == tour.createdBy || members.any((x) => x.user.id == me?.id && x.role == 'admin');
            
            Widget? trailingWidget;
            if (isAdmin && !isMe) {
               trailingWidget = Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   if (!isRemoved) ...[
                     IconButton(
                       icon: Icon(Icons.history_rounded, color: config.color, size: 18),
                       tooltip: "Include in Past Expenses",
                       onPressed: () => _confirmRetroactiveSplit(m.user),
                     ),
                     DropdownButton<String>(
                     value: m.role,
                     icon: const Icon(Icons.arrow_drop_down, size: 16),
                     style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                     items: const [
                       DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                       DropdownMenuItem(value: 'editor', child: Text('Editor')),
                       DropdownMenuItem(value: 'admin', child: Text('Admin')),
                     ],
                     onChanged: (val) {
                       if (val != null) {
                         ref.read(databaseProvider).updateMemberRole(widget.tourId, m.user.id, val);
                         ref.read(syncServiceProvider).updateMemberRole(widget.tourId, m.user.id, val).catchError((e) => debugPrint(e.toString()));
                       }
                     },
                     underline: const SizedBox(),
                   ),
                   ],
                   isRemoved 
                     ? IconButton(
                         onPressed: () => _showRestoreConfirmation(m.user), 
                         icon: const Icon(Icons.settings_backup_restore, size: 20),
                         color: config.color,
                         tooltip: "Restore",
                       )
                     : IconButton(icon: const Icon(Icons.person_remove, color: Colors.red, size: 18), onPressed: () => _showLeaveConfirmation(m.user, isRemoval: true)),
                 ],
               );
            } else {
               if (!isRemoved) {
                 trailingWidget = Container(
                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                   decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                   child: Text(m.role.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey))
                 );
               }
            }

            return Card(
              elevation: isRemoved ? 0 : 1,
              color: isRemoved ? Colors.grey.shade50 : null,
              child: Opacity(
                opacity: isRemoved ? 0.6 : 1.0,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRemoved ? Colors.grey.shade200 : config.color.withOpacity(0.1),
                    child: Text(m.user.name[0], style: TextStyle(color: isRemoved ? Colors.grey : config.color, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(
                    isMe ? "${m.user.name} (You)" : m.user.name,
                    style: TextStyle(
                      decoration: isRemoved ? TextDecoration.lineThrough : null,
                      color: isRemoved ? Colors.grey : null,
                    ),
                  ),
                  subtitle: tour.purpose.toLowerCase() == 'mess' 
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.user.phone ?? "No phone", style: const TextStyle(fontSize: 10)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.restaurant_menu, size: 14, color: isRemoved ? Colors.grey : config.color.withOpacity(0.7)),
                              const SizedBox(width: 4),
                              Text(
                                "Meal Count: ${m.mealCount.toStringAsFixed(1)}", 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 13, 
                                  color: isRemoved ? Colors.grey : Theme.of(context).colorScheme.onSurface.withOpacity(0.8)
                                ),
                              ),
                              if (isRemoved) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                                  child: const Text("REMOVED", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      )
                    : Text(m.user.phone ?? "No phone", style: TextStyle(color: isRemoved ? Colors.grey : null)),
                  onTap: !isRemoved && tour.purpose.toLowerCase() == 'mess' && (isMe || me?.id == tour.createdBy)
                    ? () => _showEditMealCountDialog(m)
                    : null,
                  trailing: trailingWidget,
                ),
              ),
            );
              },
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
    );
  }

  Widget _buildSummaryTab() {
    return SettlementScreen(tourId: widget.tourId);
  }

  Widget _buildProgramOverviewTab(Tour tour) {
    final db = ref.watch(databaseProvider);
    final config = PurposeConfig.getConfig(tour.purpose);
    final me = ref.watch(currentUserProvider).value;
    final splitsAsync = ref.watch(tourSplitsProvider(widget.tourId));
    final splits = splitsAsync.value ?? [];
    
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    final members = membersAsync.value ?? [];
    
    final usersStream = (db.select(db.users).join([
      drift.innerJoin(db.tourMembers, db.tourMembers.userId.equalsExp(db.users.id))
    ])..where(db.tourMembers.tourId.equals(widget.tourId)))
    .map((row) => row.readTable(db.users))
    .watch();

    return StreamBuilder<List<ProgramIncome>>(
      stream: (db.select(db.programIncomes)..where((t) => t.isDeleted.equals(false))).watch(), 
      builder: (context, incomeSnap) {
        final incomes = (incomeSnap.data ?? []).where((i) => i.tourId == widget.tourId).toList();
        final totalCollected = incomes.fold(0.0, (sum, item) => sum + item.amount);

        return StreamBuilder<List<Expense>>(
          stream: (db.select(db.expenses)..where((t) => t.isDeleted.equals(false))).watch(),
          builder: (context, expenseSnap) {
            final expenses = (expenseSnap.data ?? []).where((e) => e.tourId == widget.tourId).toList();
            final totalSpent = expenses.fold(0.0, (sum, item) => sum + item.amount);

            return StreamBuilder<List<Settlement>>(
              stream: (db.select(db.settlements)..where((t) => t.isDeleted.equals(false))).watch(),
              builder: (context, settlementSnap) {
                final settlements = (settlementSnap.data ?? []).where((s) => s.tourId == widget.tourId).toList();
                final currentBalance = totalCollected - totalSpent; 

                return StreamBuilder<List<User>>(
                  stream: usersStream,
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final users = userSnap.data!;
                    final userBalances = <User, double>{};
                    
                    for (final u in users) {
                      final col = incomes.where((i) => i.collectedBy == u.id).fold(0.0, (sum, i) => sum + i.amount);
                      final rec = settlements.where((s) => s.toId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                      final giv = settlements.where((s) => s.fromId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                      final spt = expenses.where((e) => e.payerId == u.id).fold(0.0, (sum, e) => sum + e.amount);
                      userBalances[u] = col + rec - giv - spt;
                    }
                    
                    final sortedUsers = List<User>.from(users)..sort((a, b) => (userBalances[b] ?? 0).compareTo(userBalances[a] ?? 0));
                    final progressVal = totalCollected > 0 ? (totalSpent / totalCollected).clamp(0.0, 1.0) : 0.0;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPremiumDashboardCard(totalCollected, totalSpent, currentBalance, progressVal, config),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Your Team", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                              if (tour.createdBy == me?.id) IconButton.filledTonal(
                                onPressed: () => showDialog(context: context, builder: (_) => AddMemberDialog(tourId: widget.tourId)),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                style: IconButton.styleFrom(
                                  backgroundColor: config.color.withOpacity(0.05),
                                  foregroundColor: config.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildMemberStatusList(sortedUsers, userBalances, config),
                          
                          const SizedBox(height: 32),
                          const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          const SizedBox(height: 16),
                          Builder(
                            builder: (context) {
                              final myRole = members.firstWhere((m) => m.user.id == me?.id, orElse: () => members.first).role;
                              final isViewer = myRole == 'viewer';
                              
                              if (isViewer) {
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.lock_outline, color: Colors.orange, size: 20),
                                      SizedBox(width: 8),
                                      Expanded(child: Text("You are a Viewer. Viewers cannot add or edit expenses.", style: TextStyle(fontSize: 12, color: Colors.orange))),
                                    ],
                                  ),
                                );
                              }
                              
                              return Row(
                                children: [
                                  Expanded(child: _buildDashboardQuickButton(Icons.add_task_rounded, "Income", config.color, () => showDialog(context: context, builder: (_) => AddIncomeDialog(tourId: widget.tourId)))),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildDashboardQuickButton(Icons.receipt_rounded, "Expense", Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId))))),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildDashboardQuickButton(Icons.swap_calls_rounded, "Transfer", Colors.teal, () => showDialog(context: context, builder: (_) => AllocateFundDialog(tourId: widget.tourId)))),
                                ],
                              );
                            }
                          ),
                          
                          const SizedBox(height: 32),
                          Row(
                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                             children: [
                               const Text("Recent Activity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                               TextButton(onPressed: () => _tabController?.animateTo(1), child: const Text("See All")),
                             ],
                          ),
                          _buildRecentTransactionsList(incomes, expenses, settlements, me?.id, splits),
                          const SizedBox(height: 80),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPremiumDashboardCard(double totalCollected, double totalSpent, double balance, double progress, PurposeConfig config) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      gradient: config.gradient,
      shadowColor: config.shadowColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("NET BALANCE", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    Container(
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                       decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                       child: Text(DateFormat('MMM dd').format(DateTime.now()), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text("৳${balance.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("TOTAL FUND", style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          Text("৳${totalCollected.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("TOTAL SPENT", style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          Text("৳${totalSpent.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.8)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${(progress * 100).toInt()}% of budget spent", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                const Icon(Icons.insights_rounded, color: Colors.white, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberStatusList(List<User> users, Map<User, double> balances, PurposeConfig config) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: users.length,
        itemBuilder: (context, index) {
          final u = users[index];
          final bal = balances[u] ?? 0.0;
          final isPos = bal > 0.1;
          final isNeg = bal < -0.1;

          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: isNeg ? 1 : (isPos ? 1 : 0),
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(isPos ? Colors.green : (isNeg ? Colors.orange : Colors.grey.shade300)),
                    ),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: config.color.withOpacity(0.1),
                      child: Text(u.name[0].toUpperCase(), style: TextStyle(color: config.color, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(u.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                Text(
                  bal.abs() < 1 ? "Settled" : "৳${bal.abs().toStringAsFixed(0)}", 
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isPos ? Colors.green : (isNeg ? Colors.orange : Colors.grey)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboardQuickButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color, {VoidCallback? onTap, IconData? actionIcon, VoidCallback? onAction}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background Gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.12), color.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(title, style: TextStyle(color: color.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                              const SizedBox(width: 4),
                              Icon(Icons.info_outline, size: 12, color: color.withOpacity(0.4)),
                            ],
                          ),
                          if (actionIcon != null)
                            Material(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: onAction,
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(actionIcon, size: 18, color: color),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text("৳${amount.toStringAsFixed(0)}", 
                        style: TextStyle(
                          color: color, 
                          fontSize: 26, 
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        )
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSummaryDetailSheet(
    String title, 
    List<ProgramIncome> incomes, 
    List<Expense> expenses, 
    List<Settlement> settlements,
    List<User> users,
    {bool isIncome = false, bool isExpense = false, bool isBalance = false}
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 12),
                
                if (isIncome) ...[
                  Text("Collected by Member", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  ...users.map((u) {
                    final amount = incomes.where((i) => i.collectedBy == u.id).fold(0.0, (s, i) => s + i.amount);
                    if (amount == 0) return const SizedBox.shrink();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundColor: Colors.green.withOpacity(0.1), child: Text(u.name[0], style: const TextStyle(color: Colors.green))),
                      title: Text(u.name),
                      trailing: Text("৳${amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  Text("Transaction History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  if (incomes.isEmpty) const Text("No income recorded yet.")
                  else ...incomes.map((i) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined, size: 20),
                    title: Text(i.source),
                    subtitle: Text(DateFormat('MMM dd').format(i.date)),
                    trailing: Text("+৳${i.amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  )),
                ],
  
                if (isExpense) ...[
                  Text("Spent by Member", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  ...users.map((u) {
                    final amount = expenses.where((e) => e.payerId == u.id).fold(0.0, (s, e) => s + e.amount);
                    if (amount == 0) return const SizedBox.shrink();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundColor: Colors.orange.withOpacity(0.1), child: Text(u.name[0], style: const TextStyle(color: Colors.orange))),
                      title: Text(u.name),
                      trailing: Text("৳${amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  Text("Category Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  if (expenses.isEmpty) const Text("No expenses recorded yet.")
                  else ...(() {
                    // Group by category
                    final map = <String, double>{};
                    for (var e in expenses) {
                      map[e.category] = (map[e.category] ?? 0.0) + e.amount;
                    }
                    return map.entries.map((entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: _getCategoryColor(entry.key).withOpacity(0.1),
                        child: Icon(_getCategoryIcon(entry.key), color: _getCategoryColor(entry.key), size: 16),
                      ),
                      title: Text(entry.key),
                      trailing: Text("-৳${entry.value.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ));
                  })(),
                ],
  
                if (isBalance) ...[
                  Text("Cash in Hand (Personal)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  ...users.map((u) {
                    final col = incomes.where((i) => i.collectedBy == u.id).fold(0.0, (sum, i) => sum + i.amount);
                    final rec = settlements.where((s) => s.toId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final giv = settlements.where((s) => s.fromId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final spt = expenses.where((e) => e.payerId == u.id).fold(0.0, (sum, e) => sum + e.amount);
                    final bal = col + rec - giv - spt;
                    if (bal.abs() < 1) return const SizedBox.shrink();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundColor: Colors.blue.withOpacity(0.1), child: Text(u.name[0], style: const TextStyle(color: Colors.blue))),
                      title: Text(u.name),
                      subtitle: Text(bal > 0 ? "Holding" : "Owed"),
                    trailing: Text("৳${bal.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.bold, color: bal >= 0 ? Colors.green : Colors.red)),
                    );
                  }).toList(),
                  const Divider(height: 32),
                  Text("Overall Summary", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  _buildDetailRow("Total Funds Collected", incomes.fold(0.0, (s, i) => s + i.amount), Colors.green),
                  _buildDetailRow("Total Group Expenses", expenses.fold(0.0, (s, e) => s + e.amount), Colors.red),
                  const Divider(),
                  _buildDetailRow("Net Program Balance", incomes.fold(0.0, (s, i) => s + i.amount) - expenses.fold(0.0, (s, e) => s + e.amount), Colors.blue, isBold: true),
                ],
                
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text("Close"),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildDetailRow(String label, double amount, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text("৳${amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: isBold ? 18 : 14)),
        ],
      ),
    );
  }

  Widget _buildSettlementInstructions(Map<User, double> balances, List<User> creditors, List<User> debtors, PurposeConfig config) {
    // Greedy algorithm for settlement instructions
    final List<Widget> items = [];
    final creditorsCopy = creditors.map((u) => {'user': u, 'bal': balances[u] ?? 0.0}).toList();
    final debtorsCopy = debtors.map((u) => {'user': u, 'bal': -(balances[u] ?? 0.0)}).toList();

    int cIdx = 0;
    int dIdx = 0;

    while (cIdx < creditorsCopy.length && dIdx < debtorsCopy.length) {
      final cAmount = creditorsCopy[cIdx]['bal'] as double;
      final dAmount = debtorsCopy[dIdx]['bal'] as double;
      final settlement = cAmount < dAmount ? cAmount : dAmount;

      final from = creditorsCopy[cIdx]['user'] as User;
      final to = debtorsCopy[dIdx]['user'] as User;

      items.add(ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(Icons.send_rounded, color: config.color, size: 20),
        title: Text.rich(TextSpan(children: [
          TextSpan(text: from.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: " pays "),
          TextSpan(text: to.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        ])),
        trailing: Text("৳${settlement.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.bold, color: config.color)),
      ));

      creditorsCopy[cIdx]['bal'] = (creditorsCopy[cIdx]['bal'] as double) - settlement;
      debtorsCopy[dIdx]['bal'] = (debtorsCopy[dIdx]['bal'] as double) - settlement;

      if ((creditorsCopy[cIdx]['bal'] as double).abs() < 0.1) cIdx++;
      if ((debtorsCopy[dIdx]['bal'] as double).abs() < 0.1) dIdx++;
    }

    return Card(
      color: config.color.withOpacity(0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: config.color.withOpacity(0.2))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: items),
      ),
    );
  }

  Widget _buildIncomesTab(Tour tour) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<ProgramIncome>>(
      stream: (db.select(db.programIncomes)..where((t) => t.tourId.equals(widget.tourId) & t.isDeleted.equals(false))).watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final incomes = snapshot.data!;
        if (incomes.isEmpty) return const Center(child: Text("No funds collected."));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: incomes.length,
          itemBuilder: (context, index) {
            final inc = incomes[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.greenAccent, child: Icon(Icons.arrow_downward, color: Colors.green)),
                title: Text(inc.source),
                trailing: Text("+৳${inc.amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAllocationsTab(Tour tour) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<Settlement>>(
      stream: (db.select(db.settlements)..where((t) => t.tourId.equals(widget.tourId) & t.isDeleted.equals(false))).watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final settlements = snapshot.data!;
        if (settlements.isEmpty) return const Center(child: Text("No allocations."));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: settlements.length,
          itemBuilder: (context, index) {
            final s = settlements[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.swap_horiz, color: Colors.white)),
                title: const Text("Transfer"),
                trailing: Text("৳${s.amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactionsList(List<ProgramIncome> incomes, List<Expense> expenses, List<Settlement> settlements, String? myId, List<ExpenseSplit> splits) {
    // Combine and sort by date/time
    final transactions = <Map<String, dynamic>>[];
    
    for (final i in incomes) {
      if (myId == null || i.collectedBy == myId) {
        transactions.add({'type': 'income', 'amount': i.amount, 'title': i.source, 'date': i.date, 'id': i.id});
      }
    }
    for (final e in expenses) {
      final isSharedWithMe = splits.any((s) => s.expenseId == e.id && s.userId == myId);
      if (myId == null || e.payerId == myId || isSharedWithMe) {
        transactions.add({'type': 'expense', 'amount': e.amount, 'title': e.title, 'date': e.createdAt, 'id': e.id});
      }
    }
    for (final s in settlements) {
      if (myId == null || s.fromId == myId || s.toId == myId) {
        transactions.add({'type': 'allocation', 'amount': s.amount, 'title': 'Fund Transfer', 'date': s.date, 'id': s.id});
      }
    }

    transactions.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    final latest = transactions.take(5).toList();

    if (latest.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(myId != null ? "No personal transactions yet." : "No transactions yet.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3))),
      );
    }

    return Column(
      children: latest.map((tx) {
        final isIncome = tx['type'] == 'income';
        final isExpense = tx['type'] == 'expense';
        return ListTile(
          visualDensity: VisualDensity.compact,
          leading: Icon(
            isIncome ? Icons.arrow_downward : (isExpense ? Icons.arrow_upward : Icons.swap_horiz),
            color: isIncome ? Colors.green : (isExpense ? Colors.red : Colors.blue),
            size: 18,
          ),
          title: Text(tx['title'], style: const TextStyle(fontSize: 14)),
          subtitle: Text(DateFormat('MMM dd, hh:mm a').format(tx['date'])),
          trailing: Text(
            "${isIncome ? '+' : (isExpense ? '-' : '')}৳${tx['amount'].toStringAsFixed(0)}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.green : (isExpense ? Colors.red : Theme.of(context).colorScheme.onSurface),
            ),
          ),
        );
      }).toList(),
    );
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () async { await ref.read(databaseProvider).deleteExpenseWithDetails(exp.id); Navigator.pop(context); }, child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _showDeleteTourConfirmation(BuildContext context, Tour tour) {
    final config = PurposeConfig.getConfig(tour.purpose);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete ${config.label}?"),
        content: Text("This will delete the ${config.label.toLowerCase()} permanently for everyone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(onPressed: () async { await ref.read(databaseProvider).deleteTourWithDetails(tour.id); Navigator.pop(context); Navigator.pop(context); }, style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text("Delete")),
        ],
      ),
    );
  }

  void _showLeaveConfirmation(User user, {required bool isRemoval}) {
    final tour = ref.read(singleTourProvider(widget.tourId)).value;
    final config = PurposeConfig.getConfig(tour?.purpose);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isRemoval ? "Remove ${config.memberLabel}" : "Leave ${config.label}"),
        content: Text(isRemoval 
          ? "This ${config.memberLabel.toLowerCase()} will be marked as 'Removed' and lose access. Their past expenses and contributions will be kept to ensure correct group balance."
          : "You will be marked as 'Left'. You can still see records but cannot add new entries."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(onPressed: () async { await ref.read(databaseProvider).markMemberAsLeft(widget.tourId, user.id); Navigator.pop(context); }, style: FilledButton.styleFrom(backgroundColor: Colors.red), child: Text(isRemoval ? "Remove" : "Leave")),
        ],
      ),
    );
  }

  void _showRestoreConfirmation(User user) {
    final tour = ref.read(singleTourProvider(widget.tourId)).value;
    final config = PurposeConfig.getConfig(tour?.purpose);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Restore ${config.memberLabel}"),
        content: Text("Do you want to restore ${user.name} to this ${config.label.toLowerCase()}? They will regain full access."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async { 
              await ref.read(databaseProvider).reactivateMember(widget.tourId, user.id); 
              Navigator.pop(context); 
            }, 
            style: FilledButton.styleFrom(backgroundColor: config.color), 
            child: const Text("Restore")
          ),
        ],
      ),
    );
  }

  void _showEditMealCountDialog(MemberWithStatus m) {
    final controller = TextEditingController(text: m.mealCount.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit Meals for ${m.user.name}"),
        content: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Total Meals", suffixText: "meals"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              final val = double.tryParse(controller.text) ?? 0.0;
              await ref.read(databaseProvider).updateMealCount(widget.tourId, m.user.id, val);
              if (mounted) Navigator.pop(context);
              ref.invalidate(tourMembersProvider(widget.tourId));
            }, 
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Widget _buildMealsTab(Tour tour) {
    final mealRecordsAsync = ref.watch(tourMealRecordsProvider(widget.tourId));
    final usersAsync = ref.watch(tourUsersProvider(widget.tourId));
    
    return mealRecordsAsync.when(
      data: (records) {
        return usersAsync.when(
          data: (users) {
            final userMap = { for (var u in users) u.id : u.name };
            
            if (records.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    const Text("No meal records found.", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MealEntryScreen(tourId: widget.tourId))),
                      icon: const Icon(Icons.add),
                      label: const Text("Enter Daily Meals"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              );
            }

            final Map<String, List<MealRecord>> grouped = {};
            for (var r in records) {
              final dateKey = DateFormat('yyyy-MM-dd').format(r.date);
              grouped.putIfAbsent(dateKey, () => []).add(r);
            }
            final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedDates.length,
              itemBuilder: (context, index) {
                final dateKey = sortedDates[index];
                final dailyRecords = grouped[dateKey]!;
                final dailyTotal = dailyRecords.fold(0.0, (sum, r) => sum + r.count);
                final date = dailyRecords.first.date;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: CircleAvatar(backgroundColor: Colors.orange.withOpacity(0.1), child: const Icon(Icons.calendar_today, size: 18, color: Colors.orange)),
                    title: Text(DateFormat('EEEE, MMM dd').format(date), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Total Meals: ${dailyTotal.toStringAsFixed(1)}"),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') {
                           Navigator.push(context, MaterialPageRoute(builder: (_) => MealEntryScreen(tourId: widget.tourId, initialDate: date)));
                        } else if (v == 'delete') {
                           _showDeleteMealDayDialog(date, dailyRecords);
                        }
                      },
                      itemBuilder: (c) => [
                         const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text("Edit Day")])),
                         const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text("Delete Day", style: TextStyle(color: Colors.red))])),
                      ],
                    ),
                    children: [
                       ...dailyRecords.map((r) => ListTile(
                         dense: true,
                         title: Text(userMap[r.userId] ?? "Unknown Member"),
                         trailing: Text("${r.count.toStringAsFixed(1)} meals"),
                       )),
                    ],
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
  }

  void _showDeleteMealDayDialog(DateTime date, List<MealRecord> records) {
     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text("Delete Day's Records?"),
         content: Text("Delete all ${records.length} meal entries for ${DateFormat('MMM dd').format(date)}?"),
         actions: [
           TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
           FilledButton(
             onPressed: () async {
               final db = ref.read(databaseProvider);
               for (var r in records) {
                 await db.deleteMealRecord(r.id, r.tourId, r.userId);
               }
               if (mounted) Navigator.pop(context);
               ref.invalidate(tourMealRecordsProvider(widget.tourId));
               ref.invalidate(tourMembersProvider(widget.tourId));
             }, 
             style: FilledButton.styleFrom(backgroundColor: Colors.red),
             child: const Text("Delete"),
           ),
         ],
       ),
     );
  }

  void _showMemberSystemInfo() {
    final tour = ref.read(singleTourProvider(widget.tourId)).value;
    final config = PurposeConfig.getConfig(tour?.purpose);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.people_alt, color: Colors.teal),
            const SizedBox(width: 10),
            Text("${config.memberLabel} System"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("How to add ${config.memberLabel.toLowerCase()}:", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("1. Share the 'Invite Code' from the top-right button."),
              const Text("2. Other people use 'Join with Code' from their home screen."),
              const SizedBox(height: 16),
              const Text("Role & Permissions:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("• The Creator (Admin) can add ${config.memberLabel.toLowerCase()}, manage all data, and remove others."),
              Text("• Joined ${config.memberLabel} can only see data and edit their own meal records."),
              const SizedBox(height: 16),
              const Text("Removing Member:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("• Removing someone revokes their access to the ${config.label.toLowerCase()} immediately."),
              const Text("• Their financial history is kept for group balance correctness."),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Got it")),
        ],
      ),
    );
  }

  void _confirmRetroactiveSplit(User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Include in Past Expenses"),
        content: Text("Do you want to redistribute all existing expenses equally to include ${user.name}? This will change everyone's balances."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final currentUserId = ref.read(currentUserProvider).value?.id;
                final syncService = ref.read(syncServiceProvider);
                await syncService.applyRetroactiveSplitLocally(widget.tourId, user.id);
                if (currentUserId != null) {
                  syncService.retroactiveSplit(widget.tourId, user.id, currentUserId)
                    .catchError((e) => debugPrint('Server sync failed: $e'));
                }
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member included in past expenses successfully!')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text("Yes"),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.05)..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

