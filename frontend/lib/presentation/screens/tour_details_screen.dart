import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' as drift;
import 'user_profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/data/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/add_income_dialog.dart';
import '../widgets/allocate_fund_dialog.dart';
import 'add_expense_screen.dart';
import 'create_tour_screen.dart';
import 'settlement_screen.dart';
import 'meal_entry_screen.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/local/app_database.dart';
import '../../domain/logic/purpose_config.dart';
import 'ai_coach_screen.dart';
import '../widgets/premium_card.dart';
import '../widgets/smooth_page_transition.dart';

class TourDetailsScreen extends ConsumerStatefulWidget {
  final String tourId;
  final String tourName;
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
  int _unreadNotificationCount = 0;
  Set<String> _currentNotificationKeys = <String>{};
  Timer? _notificationTimer;
  bool _isLocalOnlyTour = false;
  bool _isSyncingTour = false;

  String _formatMealCount(double value) {
    var text = value.toStringAsFixed(2);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  @override
  void initState() {
    super.initState();
    _selectedFilterMemberId = widget.initialFilterMemberId;
    Future.microtask(() => _refreshNotifications(showSnackBar: false));
    _notificationTimer = Timer.periodic(const Duration(seconds: 45), (_) => _refreshNotifications(showSnackBar: false));
    Future.microtask(_loadLocalOnlyState);
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadLocalOnlyState() async {
    final db = ref.read(databaseProvider);
    final isLocalOnly = await db.isTourLocalOnly(widget.tourId);
    if (!mounted) return;
    setState(() => _isLocalOnlyTour = isLocalOnly);
  }

  Future<bool> _syncTourNow({bool showSuccessSnack = true}) async {
    if (_isSyncingTour) return false;
    final user = ref.read(currentUserProvider).value;
    if (user == null) return false;
    if (mounted) setState(() => _isSyncingTour = true);
    try {
      await ref.read(syncServiceProvider).startSync(user.id);
      await _loadLocalOnlyState();
      if (showSuccessSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync completed.')));
      }
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: ')));
      return false;
    } finally {
      if (mounted) setState(() => _isSyncingTour = false);
    }
  }

  Future<void> _openEditForCloudSync(Tour tour) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateTourScreen(initialTour: tour)));
    if (!mounted) return;
    await _loadLocalOnlyState();
    if (!_isLocalOnlyTour) await _syncTourNow(showSuccessSnack: false);
  }

  Future<void> _refreshNotifications({bool showSnackBar = false}) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    try {
      final invitations = await ref.read(syncServiceProvider).getMyInvitations();
      final notificationKeys = <String>{};
      for (final inv in invitations) {
        final tourId = inv['tourId']?.toString() ?? inv['tour']?['id']?.toString();
        if (tourId != null) notificationKeys.add('invite_');
      }
      final db = ref.read(databaseProvider);
      final approvalRows = await db.customSelect(
        \"SELECT id FROM join_requests WHERE tour_id = ? AND status = 'pending'\",
        variables: [drift.Variable.withString(widget.tourId)],
      ).get();
      for (final row in approvalRows) {
        notificationKeys.add('approval_');
      }
      final nextUnreadCount = notificationKeys.length;
      if (mounted) setState(() { _unreadNotificationCount = nextUnreadCount; _currentNotificationKeys = notificationKeys; });
    } catch (e) {
      debugPrint('Notification refresh failed: ');
    }
  }

  void _initTabController(Tour tour) {
    final String p = tour.purpose.toLowerCase();
    final bool isProg = p == 'event' || p == 'business';
    final bool isMess = p == 'mess';
    final int newLength = isProg ? 5 : (isMess ? 4 : 3);
    if (_tabController == null || _tabLength != newLength) {
      _tabController?.dispose();
      _tabLength = newLength;
      _isProgram = isProg;
      _tabController = TabController(length: _tabLength, vsync: this);
      _tabController!.addListener(() { if (mounted) setState(() {}); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));
    return tourAsync.when(
      data: (tour) {
        if (tour == null) return Scaffold(appBar: AppBar(title: const Text(\"Deleted\")), body: const Center(child: Text(\"Deleted\")));
        _initTabController(tour);
        final config = PurposeConfig.getConfig(tour.purpose);
        final me = ref.watch(currentUserProvider).value;
        final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
        final isAdmin = me?.id == tour.createdBy || (membersAsync.value?.any((m) => m.user.id == me?.id && m.role == 'admin') ?? false);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: config.color,
            foregroundColor: Colors.white,
            title: Text(tour.name),
            actions: [
              IconButton(icon: const Icon(Icons.edit), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateTourScreen(initialTour: tour)))),
              IconButton(icon: const Icon(Icons.share), onPressed: () => _generateAndShowCode(context, tour)),
              if (isAdmin)
                IconButton(icon: const Icon(Icons.delete), onPressed: () => _showDeleteTourConfirmation(context, tour)),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: _isProgram 
                ? [const Tab(text: 'DASHBOARD'), const Tab(text: 'INCOME'), const Tab(text: 'EXPENSES'), const Tab(text: 'TEAM'), const Tab(text: 'BANK')]
                : [Tab(text: config.expenseListLabel), Tab(text: config.memberLabel), if (tour.purpose == 'mess') const Tab(text: 'MEALS'), const Tab(text: 'SUMMARY')],
            ),
          ),
          body: Column(
            children: [
              if (!tour.isSynced)
                Container(
                  color: Colors.orange.shade100,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_problem, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Not synced to cloud.')),
                      TextButton(onPressed: () => _isLocalOnlyTour ? _openEditForCloudSync(tour) : _syncTourNow(), child: Text(_isLocalOnlyTour ? 'Go Global' : 'Sync')),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _isProgram 
                    ? [_buildProgramOverviewTab(tour), _buildIncomesTab(tour), _buildExpensesTab(tour), _buildMembersTab(tour), _buildAllocationsTab(tour)]
                    : [_buildExpensesTab(tour), _buildMembersTab(tour), if (tour.purpose == 'mess') _buildMealsTab(tour), _buildSummaryTab()],
                ),
              ),
            ],
          ),
          floatingActionButton: _buildFab(tour),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(body: Center(child: Text(\"Error: \"))),
    );
  }

  Widget? _buildFab(Tour tour) {
    final int index = _tabController?.index ?? 0;
    final config = PurposeConfig.getConfig(tour.purpose);
    return FloatingActionButton(
      backgroundColor: config.color,
      onPressed: () {
        if (_isProgram) {
          if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId)));
        } else {
          if (index == 0) Navigator.push(context, MaterialPageRoute(builder: (_) => AddExpenseScreen(tourId: widget.tourId)));
          if (index == 1) showDialog(context: context, builder: (_) => AddMemberDialog(tourId: widget.tourId));
        }
      },
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  void _generateAndShowCode(BuildContext context, Tour tour) async {
    if (!tour.isSynced && !_isLocalOnlyTour) {
      await _syncTourNow(showSuccessSnack: false);
    }
    if (_isLocalOnlyTour) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local-only tours cannot be shared via code.')));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Code'),
        content: SelectableText(tour.inviteCode ?? 'No code yet', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildExpensesTab(Tour tour) {
    final expensesAsync = ref.watch(expensesProvider(widget.tourId));
    return expensesAsync.when(
      data: (exps) => ListView.builder(
        itemCount: exps.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(exps[i].expense.title),
          subtitle: Text(exps[i].expense.amount.toString()),
          trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => _showDeleteDialog(context, exps[i].expense)),
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (e, s) => Text(e.toString()),
    );
  }

  Widget _buildMembersTab(Tour tour) {
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    return membersAsync.when(
      data: (mems) => Column(
        children: [
          _buildJoinRequests(tour),
          Expanded(
            child: ListView.builder(
              itemCount: mems.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(mems[i].user.name),
                subtitle: Text(mems[i].role),
              ),
            ),
          ),
        ],
      ),
      loading: () => const CircularProgressIndicator(),
      error: (e, s) => Text(e.toString()),
    );
  }

  Widget _buildJoinRequests(Tour tour) {
    final db = ref.read(databaseProvider);
    return StreamBuilder<List<JoinRequest>>(
      stream: (db.select(db.joinRequests)..where((t) => t.tourId.equals(widget.tourId) & t.status.equals('pending'))).watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        return Container(
          color: Colors.amber.shade50,
          child: Column(
            children: snapshot.data!.map((r) => ListTile(
              title: Text(r.userName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _handleJoinRequest(r, 'approved')),
                  IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _handleJoinRequest(r, 'rejected')),
                ],
              ),
            )).toList(),
          ),
        );
      },
    );
  }

  Future<void> _handleJoinRequest(JoinRequest r, String status) async {
    try {
      await ref.read(syncServiceProvider).handleJoinRequest(r.id, status);
      final db = ref.read(databaseProvider);
      await (db.update(db.joinRequests)..where((t) => t.id.equals(r.id))).write(JoinRequestsCompanion(status: drift.Value(status)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _buildMealsTab(Tour tour) => MealEntryScreen(tourId: widget.tourId);
  Widget _buildSummaryTab() => SettlementScreen(tourId: widget.tourId);
  Widget _buildProgramOverviewTab(Tour tour) => const Center(child: Text('Overview'));
  Widget _buildIncomesTab(Tour tour) => const Center(child: Text('Incomes'));
  Widget _buildAllocationsTab(Tour tour) => const Center(child: Text('Allocations'));

  void _showDeleteDialog(BuildContext context, Expense exp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(\"Delete?\"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(\"Cancel\")),
          TextButton(onPressed: () async { await ref.read(databaseProvider).deleteExpenseWithDetails(exp.id); Navigator.pop(context); }, child: const Text(\"Delete\")),
        ],
      ),
    );
  }

  void _showDeleteTourConfirmation(BuildContext context, Tour tour) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(\"Delete Tour?\"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(\"Cancel\")),
          TextButton(onPressed: () async { await ref.read(databaseProvider).deleteTourWithDetails(tour.id); Navigator.pop(context); Navigator.pop(context); }, child: const Text(\"Delete\")),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}