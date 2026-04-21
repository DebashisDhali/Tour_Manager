import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart' as models;
import '../../domain/logic/settlement_calculator.dart';
import 'package:frontend/data/providers/app_providers.dart';
import 'final_receipt_screen.dart';
import 'tour_details_screen.dart';
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

    final usersAsync = ref.watch(tourUsersProvider(tourId));
    final expensesAsync = ref.watch(tourExpensesProvider(tourId));
    final splitsAsync = ref.watch(tourSplitsProvider(tourId));
    final settlementsAsync = ref.watch(tourSettlementsProvider(tourId));
    final payersAsync = ref.watch(tourPayersProvider(tourId));
    final membersAsync = ref.watch(tourMembersProvider(tourId));
    final mealRecordsAsync = ref.watch(tourMealRecordsProvider(tourId));
    final incomesAsync = ref.watch(tourIncomesProvider(tourId));

    if (usersAsync.isLoading ||
        expensesAsync.isLoading ||
        splitsAsync.isLoading ||
        tourAsync.isLoading ||
        settlementsAsync.isLoading ||
        payersAsync.isLoading ||
        membersAsync.isLoading ||
        mealRecordsAsync.isLoading ||
        incomesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (usersAsync.hasError ||
        expensesAsync.hasError ||
        splitsAsync.hasError ||
        tourAsync.hasError ||
        settlementsAsync.hasError ||
        payersAsync.hasError ||
        membersAsync.hasError ||
        mealRecordsAsync.hasError ||
        incomesAsync.hasError) {
      return const Center(
          child: Text("Error loading settlement data",
              style: TextStyle(color: Colors.red)));
    }

    final users = usersAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];
    final tourSplits = splitsAsync.value ?? [];
    final myId = ref.watch(currentUserProvider).value?.id;
    final previousSettlements = (settlementsAsync.value ?? []).toList();
    final tourPayers = payersAsync.value ?? [];
    final tourMembers = membersAsync.value ?? [];
    final mealRecords = mealRecordsAsync.value ?? [];
    final incomes = incomesAsync.value ?? [];

    if (tour == null) return const Center(child: Text("Data not found"));

    final fallbackUsers = tourMembers.map((m) => m.user).toList();
    final settlementUsers = users.isNotEmpty ? users : fallbackUsers;

    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final equalShare =
        settlementUsers.isEmpty ? 0.0 : totalCost / settlementUsers.length;

    final activeUserIds = settlementUsers.map((u) => u.id).toSet();
    final activeTourMembers = tourMembers
        .where((m) => m.status == 'active' && activeUserIds.contains(m.user.id))
        .toList();
    final mealCounts = <String, double>{};
    for (final record in mealRecords) {
      if (activeUserIds.contains(record.userId)) {
        mealCounts[record.userId] =
            (mealCounts[record.userId] ?? 0.0) + record.count;
      }
    }
    if (mealCounts.isEmpty) {
      for (var m in activeTourMembers) {
        mealCounts[m.user.id] = m.mealCount;
      }
    }
    final calculator = SettlementCalculator();

    final instructions = calculator.calculate(
      expenses,
      tourSplits,
      tourPayers,
      settlementUsers,
      previousSettlements,
      purpose: tour.purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );

    final balanceDetailsMap = calculator.getFullBalances(
      expenses: expenses,
      splits: tourSplits,
      expensePayers: tourPayers,
      users: settlementUsers,
      previousSettlements: previousSettlements,
      purpose: tour.purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );

    // Calculate meal rate for display (SINGLE SOURCE OF TRUTH)
    final totalMealCost = expenses
        .where((e) => e.messCostType == 'meal')
        .fold(0.0, (s, e) => s + e.amount);

    // Calculate fixed cost per person (divided by ALL members)
    final totalFixedCost = expenses
        .where((e) => e.messCostType == 'fixed')
        .fold(0.0, (s, e) => s + e.amount);
    final fixedCostPerPerson =
        users.isNotEmpty && tour.purpose.toLowerCase() == 'mess'
            ? totalFixedCost / settlementUsers.length
            : 0.0;

    // Only count members who actually participated (have meal count > 0)
    final totalMeals = mealCounts.values.fold(0.0, (s, c) => s + c);
    final mealRate = totalMeals > 0 ? totalMealCost / totalMeals : 0.0;

    // Check permissions
    final myMember = tourMembers.where((m) => m.user.id == myId).firstOrNull;
    final myRole = myMember?.role ?? 'viewer';
    final isAdminOrEditor = myRole == 'admin' || myRole == 'editor';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle("${config.label} Summary", config.color),
            Tooltip(
              message:
                  myMember == null ? 'Only members can download receipts' : '',
              child: TextButton.icon(
                onPressed: myMember != null
                    ? () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    FinalReceiptScreen(tourId: tourId)));
                      }
                    : null,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text("Export Report",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor:
                      myMember != null ? config.color : Colors.grey,
                ),
              ),
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
                  _buildStatItem(
                      context,
                      "Total Cost",
                      "৳${totalCost.toStringAsFixed(0)}",
                      Icons.account_balance_wallet_rounded,
                      config.color),
                  Container(
                      width: 1,
                      height: 40,
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.1)),
                  if (tour.purpose.toLowerCase() == 'mess')
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStatItem(
                            context,
                            "Rent/Fixed",
                            "৳${fixedCostPerPerson.toStringAsFixed(0)}",
                            Icons.home_rounded,
                            config.color),
                        const SizedBox(height: 12),
                        _buildStatItem(
                            context,
                            "Meal Rate",
                            "৳${mealRate.toStringAsFixed(2)}/meal",
                            Icons.restaurant_menu_rounded,
                            config.color),
                      ],
                    )
                  else
                    _buildStatItem(context, "Members", "${users.length} people",
                        Icons.group_rounded, config.color),
                ],
              ),
              // Show equal-split hint only when all shares are equal
              if (tour.purpose.toLowerCase() != 'mess') ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: config.color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: config.color.withValues(alpha: 0.7)),
                      const SizedBox(width: 6),
                      Text(
                        "Equal split = ৳${equalShare.toStringAsFixed(0)} per person",
                        style: TextStyle(
                            fontSize: 11,
                            color: config.color.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ], // Show mess mode explanation
              if (tour.purpose.toLowerCase() == 'mess') ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: config.color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 13,
                              color: config.color.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Rent shared by all members (even if absent)",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: config.color.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.restaurant_menu_rounded,
                              size: 13,
                              color: config.color.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Meals charged only for those who ate",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: config.color.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),
        _buildSectionTitle("Individual Balances", config.color),
        ...users.map((u) {
          final nid = u.id.toLowerCase();
          final details = balanceDetailsMap[nid] ?? balanceDetailsMap[u.id];
          if (details == null) return const SizedBox.shrink();

          final balance = details.net;
          final isSettled = balance.abs() < 0.1;
          final isCreditor = balance > 0.1;
          // Detect if this member has a custom (non-equal) share
          final hasCustomShare = tour.purpose.toLowerCase() != 'mess' &&
              users.length > 1 &&
              (details.share - equalShare).abs() > 1.0;

          // Visual bar: proportion of paid vs share
          final maxVal = [details.paid, details.share, 1.0]
              .reduce((a, b) => a > b ? a : b);
          final paidRatio = details.paid / maxVal;
          final shareRatio = details.share / maxVal;

          final netColor = isSettled
              ? Theme.of(context).disabledColor
              : (isCreditor ? Colors.green.shade600 : Colors.redAccent);

          return InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TourDetailsScreen(
                  tourId: tourId,
                  tourName: tour.name,
                  initialFilterMemberId: u.id,
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(20),
            child: PremiumCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // — Header row —
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: config.color.withValues(alpha: 0.12),
                        child: Text(u.name[0].toUpperCase(),
                            style: TextStyle(
                                color: config.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            if (hasCustomShare) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('custom',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange)),
                              ),
                            ],
                            const Spacer(),
                            Icon(Icons.receipt_long_rounded,
                                size: 13,
                                color: config.color.withValues(alpha: 0.4)),
                            const SizedBox(width: 3),
                            Icon(Icons.chevron_right_rounded,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.25)),
                          ],
                        ),
                      ),
                      // Net balance badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: netColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${isCreditor ? '+' : ''}${balance.toStringAsFixed(0)} ৳",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: netColor),
                            ),
                            Text(
                              isSettled
                                  ? "Settled ✓"
                                  : (isCreditor ? "Will receive" : "Will pay"),
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: netColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // — Paid row —
                  Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded,
                          size: 13, color: Colors.green.shade600),
                      const SizedBox(width: 6),
                      Text('Paid',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700)),
                      const Spacer(),
                      Text(
                        '৳${details.paid.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.green.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Paid progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: paidRatio.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor:
                          Theme.of(context).dividerColor.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(Colors.green.shade400),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // — Share row —
                  Row(
                    children: [
                      const Icon(Icons.arrow_downward_rounded,
                          size: 13, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Text(
                        hasCustomShare ? 'Share  (≠ equal)' : 'Share',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6)),
                      ),
                      if (hasCustomShare) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message:
                              'Equal share = ৳${equalShare.toStringAsFixed(0)}\nActual share = ৳${details.share.toStringAsFixed(0)}',
                          child: Icon(Icons.help_outline_rounded,
                              size: 12,
                              color: Colors.orange.withValues(alpha: 0.7)),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '৳${details.share.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Share progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: shareRatio.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor:
                          Theme.of(context).dividerColor.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(
                          Colors.redAccent.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
            ),
          ); // closes InkWell
        }),
        const SizedBox(height: 32),
        _buildSectionTitle("Settlement Guide", config.color),
        if (instructions.isEmpty)
          PremiumCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(Icons.verified_rounded,
                    size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text("Perfectly Settled!",
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -0.5)),
                Text("All accounts are balanced.",
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else ...[
          _buildVisualFlow(context, ref, instructions, config,
              canManage: isAdminOrEditor),
        ],
        if (previousSettlements.isNotEmpty) ...[
          const SizedBox(height: 32),
          _buildSectionTitle("Recent Payments", config.color),
          ...previousSettlements.reversed.take(5).map((s) {
            final fromUser = users.firstWhere((u) => u.id == s.fromId,
                orElse: () => models.User(
                    id: '',
                    name: 'Deleted User',
                    phone: '',
                    createdAt: DateTime.now(),
                    purpose: '',
                    isSynced: false,
                    isMe: false,
                    isDeleted: false));
            final toUser = users.firstWhere((u) => u.id == s.toId,
                orElse: () => models.User(
                    id: '',
                    name: 'Deleted User',
                    phone: '',
                    createdAt: DateTime.now(),
                    purpose: '',
                    isSynced: false,
                    isMe: false,
                    isDeleted: false));

            return PremiumCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 24),
                title: Text("${fromUser.name} ➔ ${toUser.name}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(DateFormat('MMM dd, hh:mm a').format(s.date),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500)),
                trailing: Text("৳${s.amount.toStringAsFixed(0)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                onLongPress: isAdminOrEditor
                    ? () => _confirmDeleteSettlement(context, ref, s)
                    : null,
              ),
            );
          }),
        ],
        const SizedBox(height: 24),
        if (tour.purpose.toLowerCase() == 'mess' && isAdminOrEditor)
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => _confirmCloseMonth(
                  context, ref, tour, balanceDetailsMap, users),
              icon: const Icon(Icons.next_plan_rounded),
              label: const Text("Close Month & Carry Balances",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: config.color,
                side: BorderSide(color: config.color, width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
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
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 1.2)),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value,
      IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 12),
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.5)),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _confirmCloseMonth(BuildContext context, WidgetRef ref, models.Tour tour,
      Map<String, UserBalanceDetails> balanceMap, List<models.User> users) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("Close Month session?"),
        content: const Text(
            "This will finalize current month and carry forward balances as primary funds in a new month."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          FilledButton(
            onPressed: () => _closeMonth(context, ref, tour, balanceMap, users),
            child: const Text("Finalize Now"),
          ),
        ],
      ),
    );
  }

  Future<void> _closeMonth(
      BuildContext context,
      WidgetRef ref,
      models.Tour tour,
      Map<String, UserBalanceDetails> balanceMap,
      List<models.User> users) async {
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
      isDeleted: false,
    ));

    // 2. Add Members & Carry Forward Balances
    for (var u in users) {
      await db.into(db.tourMembers).insert(models.TourMember(
            tourId: nextMonthId,
            userId: u.id,
            isSynced: false,
            isDeleted: false,
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
          description: balance > 0
              ? 'Surplus from previous session'
              : 'Due from previous session',
          collectedBy: u.id,
          date: DateTime.now(),
          isSynced: false,
          isDeleted: false,
        ));
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("New session created successfully!")));
      Navigator.pop(context);
    }
  }

  Widget _buildVisualFlow(BuildContext context, WidgetRef ref,
      List<SettlementInstruction> instructions, PurposeConfig config,
      {required bool canManage}) {
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
                  CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                      child: const Icon(Icons.arrow_upward_rounded,
                          size: 14, color: Colors.redAccent)),
                  const SizedBox(width: 8),
                  Text(payer,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  Text(" should pay:",
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(left: 11, top: 4, bottom: 4),
                child: DottedLine(height: 20),
              ),
              ...receivers.map((r) => Padding(
                    padding: const EdgeInsets.only(left: 24, bottom: 12),
                    child: InkWell(
                      onTap: canManage
                          ? () => _markAsPaid(context, ref, r, config)
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: config.color.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: config.color.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          children: [
                            Text("৳${r.amount.toStringAsFixed(0)}",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    color: config.color)),
                            const SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded,
                                size: 16,
                                color: Theme.of(context).disabledColor),
                            const SizedBox(width: 8),
                            CircleAvatar(
                                radius: 10,
                                backgroundColor:
                                    config.color.withValues(alpha: 0.2),
                                child: Text(r.receiverName[0],
                                    style: TextStyle(
                                        fontSize: 8,
                                        color: config.color,
                                        fontWeight: FontWeight.bold))),
                            const SizedBox(width: 8),
                            Text(r.receiverName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const Spacer(),
                            if (canManage)
                              const Text("PAID?",
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green))
                            else
                              Icon(Icons.lock_outline_rounded,
                                  size: 14,
                                  color: Theme.of(context).disabledColor),
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

  void _markAsPaid(BuildContext context, WidgetRef ref, SettlementInstruction r,
      PurposeConfig config) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Confirm Payment"),
        content: Text(
            "Confirm that ${r.payerName} paid ৳${r.amount.toStringAsFixed(0)} to ${r.receiverName}?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
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
                isDeleted: false,
              );
              await database.createSettlement(settlement);
              if (context.mounted) Navigator.pop(context);
              ref
                  .read(syncServiceProvider)
                  .startSync(r.payerId)
                  .catchError((e) => debugPrint("Sync failed: $e"));
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSettlement(
      BuildContext context, WidgetRef ref, models.Settlement s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Undo Transaction?"),
        content: const Text(
            "This will remove this payment record and revert the balance."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () async {
                final database = ref.read(databaseProvider);
                await database.deleteSettlement(s.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text("Undo",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold))),
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
        color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
