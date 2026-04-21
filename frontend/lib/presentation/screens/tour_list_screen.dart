import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:frontend/data/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'create_tour_screen.dart';
import 'tour_details_screen.dart';
import 'package:intl/intl.dart';
import 'user_profile_screen.dart';
import '../../domain/logic/purpose_config.dart';
import '../../data/local/app_database.dart' as models;
import '../widgets/premium_card.dart';
import '../widgets/app_tour_overlay.dart';
import '../widgets/app_search_sheet.dart';
import '../widgets/sync_handler.dart';
import '../widgets/no_internet_sheet.dart';
import '../widgets/smooth_page_transition.dart';

class TourListScreen extends ConsumerStatefulWidget {
  const TourListScreen({super.key});

  @override
  ConsumerState<TourListScreen> createState() => _TourListScreenState();
}

class _TourListScreenState extends ConsumerState<TourListScreen> {
  // ── App Tour GlobalKeys ──
  final _syncKey = GlobalKey();
  final _tabBarKey = GlobalKey();
  final _fabKey = GlobalKey();
  final _profileKey = GlobalKey();
  final _joinCodeAppBarKey = GlobalKey();
  final _tourOverlayKey = GlobalKey<AppTourOverlayState>();
  int _unreadNotificationCount = 0;
  Set<String> _currentNotificationKeys = <String>{};
  Timer? _notificationTimer;
  ProviderSubscription<AsyncValue<bool>>? _unsyncedSub;
  double? _edgeSwipeStartX;
  bool _edgeSwipeTracking = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _triggerInitialSync());
    Future.microtask(() => _refreshNotifications(showSnackBar: true));
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refreshNotifications(),
    );
    // Check if app tour needs to run (after first frame renders)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartTour();
    });

    // Keep a lightweight listener only for this screen lifecycle.
    // Main auto-sync orchestration is handled by SyncHandler to avoid duplicate sync storms.
    _unsyncedSub = ref.listenManual(hasUnsyncedChangesProvider, (_, __) {});
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _unsyncedSub?.close();
    super.dispose();
  }

  Future<void> _checkAndStartTour() async {
    final prefs = await SharedPreferences.getInstance();
    final tourDone = prefs.getBool('app_tour_done') ?? false;
    debugPrint('🎯 App Tour Check: tourDone=$tourDone');
    if (!tourDone && mounted) {
      // Slight delay so the UI is fully rendered
      await Future.delayed(const Duration(milliseconds: 800));
      debugPrint('🎯 Starting App Tour overlay');
      _tourOverlayKey.currentState?.startTour();
    }
  }

  /// Public method to reset and restart tour (callable from anywhere)
  void restartAppTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_tour_done', false);
    if (mounted) {
      _tourOverlayKey.currentState?.startTour();
    }
  }

  Future<void> _completeAppTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_tour_done', true);
  }

  List<TourStep> _buildTourSteps() {
    return [
      TourStep(
        targetKey: _tabBarKey,
        title: 'আপনার ড্যাশবোর্ড',
        description:
            'Activity Feed-এ সাম্প্রতিক খরচ ও ইনকাম দেখুন। Tours ট্যাবে আপনার সব ট্যুর-এর তালিকা পাবেন।',
        icon: Icons.dashboard_rounded,
        accentColor: const Color(0xFF6366F1),
      ),
      TourStep(
        targetKey: _syncKey,
        title: 'ডেটা সিঙ্ক করুন',
        description:
            'এই বাটনে ট্যাপ করলে আপনার সব ডেটা সার্ভারের সাথে আপডেট হবে। অন্য মেম্বাররাও তখন আপডেট পাবেন।',
        icon: Icons.sync_rounded,
        accentColor: const Color(0xFF0EA5E9),
      ),
      TourStep(
        targetKey: _profileKey,
        title: 'আপনার প্রোফাইল',
        description: 'এখানে আপনার নাম, ইমেইল আর সেটিংস পরিবর্তন করতে পারবেন।',
        icon: Icons.person_rounded,
        accentColor: const Color(0xFF8B5CF6),
      ),
      TourStep(
        targetKey: _fabKey,
        title: 'নতুন ট্যুর তৈরি করুন',
        description:
            'এই + বাটনে ক্লিক করে নতুন ট্যুর, ট্রিপ, ইভেন্ট বা মেস তৈরি করুন। সবার খরচ এক জায়গায় হিসাব হবে!',
        icon: Icons.add_circle_rounded,
        accentColor: const Color(0xFF10B981),
      ),
      TourStep(
        targetKey: _joinCodeAppBarKey,
        title: 'কোড দিয়ে যোগ দিন',
        description:
            'অন্যের ট্যুরে যোগ দিতে 6-digit invite code ব্যবহার করুন। Home screen-এ "Join with Code" অপশনটি ব্যবহার করুন।',
        icon: Icons.qr_code_rounded,
        accentColor: const Color(0xFFF59E0B),
      ),
    ];
  }

  Future<void> _triggerInitialSync() async {
    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      try {
        await ref.read(syncServiceProvider).startSync(user.id);
        await _refreshNotifications(showSnackBar: true);
      } catch (e) {
        debugPrint("Initial auto-sync failed: $e");
      }
    }
  }

  Future<void> _refreshNotifications({bool showSnackBar = false}) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    try {
      final invitations =
          await ref.read(syncServiceProvider).getMyInvitations();
      final uniqueTourIds = <String>{};
      final notificationKeys = <String>{};
      for (final inv in invitations) {
        final tour = inv['tour'] is Map
            ? Map<String, dynamic>.from(inv['tour'] as Map)
            : <String, dynamic>{};
        final tourId = inv['tourId']?.toString() ?? tour['id']?.toString();
        if (tourId != null && tourId.isNotEmpty) {
          uniqueTourIds.add(tourId);
          notificationKeys.add('invite_$tourId');
        }
      }

      final db = ref.read(databaseProvider);
      final approvalRows = await db.customSelect(
        '''
        SELECT DISTINCT jr.id AS request_id
        FROM join_requests jr
        INNER JOIN tour_members tm ON tm.tour_id = jr.tour_id
        WHERE jr.status = 'pending'
          AND LOWER(tm.user_id) = LOWER(?)
          AND tm.status = 'active'
          AND (LOWER(tm.role) = 'admin' OR LOWER(tm.role) = 'editor')
        ''',
        variables: [Variable.withString(user.id)],
      ).get();
      for (final row in approvalRows) {
        final reqId = row.data['request_id']?.toString();
        if (reqId != null && reqId.isNotEmpty) {
          notificationKeys.add('approval_$reqId');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final seenKey = 'seen_notification_keys_${user.id}';
      final seenKeys = prefs.getStringList(seenKey)?.toSet() ?? <String>{};
      final nextUnreadCount =
          notificationKeys.where((k) => !seenKeys.contains(k)).length;

      final shouldShowSnack =
          showSnackBar && mounted && nextUnreadCount > _unreadNotificationCount;

      if (!mounted) return;
      final hasCountChanged = nextUnreadCount != _unreadNotificationCount;
      final hasKeysChanged =
          notificationKeys.length != _currentNotificationKeys.length ||
              !notificationKeys.containsAll(_currentNotificationKeys);

      if (hasCountChanged || hasKeysChanged) {
        setState(() {
          _unreadNotificationCount = nextUnreadCount;
          _currentNotificationKeys = notificationKeys;
        });
      }

      if (shouldShowSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'You have $nextUnreadCount unread notification${nextUnreadCount > 1 ? 's' : ''}.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Notification check failed: $e');
    }
  }

  Future<void> _openProfileAndMarkSeen(models.User user) async {
    final prefs = await SharedPreferences.getInstance();
    final seenKey = 'seen_notification_keys_${user.id}';
    final existingSeen = prefs.getStringList(seenKey)?.toSet() ?? <String>{};
    existingSeen.addAll(_currentNotificationKeys);

    final trimmedSeen = existingSeen.toList();
    if (trimmedSeen.length > 1000) {
      trimmedSeen.removeRange(0, trimmedSeen.length - 1000);
    }

    await prefs.setStringList(seenKey, trimmedSeen);

    if (mounted) {
      setState(() => _unreadNotificationCount = 0);
    }

    if (!mounted) return;
    navigateWithTransition(context,
        builder: () => UserProfileScreen(user: user, isMe: true));
  }

  void _handleEdgeSwipeDown(PointerDownEvent event) {
    final width = MediaQuery.of(context).size.width;
    final edgeThreshold = width - 28;
    if (event.position.dx >= edgeThreshold) {
      _edgeSwipeTracking = true;
      _edgeSwipeStartX = event.position.dx;
    }
  }

  void _handleEdgeSwipeMove(PointerMoveEvent event) {
    if (!_edgeSwipeTracking || _edgeSwipeStartX == null) return;

    final deltaX = event.position.dx - _edgeSwipeStartX!;
    if (deltaX <= -80) {
      final user = ref.read(currentUserProvider).value;
      if (user != null) {
        _edgeSwipeTracking = false;
        _edgeSwipeStartX = null;
        _openProfileAndMarkSeen(user);
      }
    }
  }

  void _resetEdgeSwipe(PointerEvent event) {
    _edgeSwipeTracking = false;
    _edgeSwipeStartX = null;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserAsync = ref.watch(currentUserProvider);

    return currentUserAsync.when(
      data: (user) {
        final config = PurposeConfig.getConfig(user?.purpose);
        final lastSync =
            user != null ? ref.watch(lastSyncProvider(user.id)).value : null;
        String syncDisplay = 'Not synced';
        if (lastSync != null) {
          final parsed = DateTime.tryParse(lastSync);
          if (parsed != null) {
            syncDisplay =
                'Synced ${DateFormat('hh:mm a').format(parsed.toLocal())}';
          }
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleEdgeSwipeDown,
          onPointerMove: _handleEdgeSwipeMove,
          onPointerUp: _resetEdgeSwipe,
          onPointerCancel: _resetEdgeSwipe,
          child: AppTourOverlay(
            key: _tourOverlayKey,
            steps: _buildTourSteps(),
            onComplete: _completeAppTour,
            child: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  toolbarHeight: 72,
                  titleSpacing: 18,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        config.pluralLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 21,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.sync_rounded,
                            size: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            syncDisplay,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton.filledTonal(
                        key: _joinCodeAppBarKey,
                        onPressed: () => _showJoinDialog(context, config),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        tooltip: 'Join with Code',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(38, 38),
                          backgroundColor: config.color.withValues(alpha: 0.14),
                          foregroundColor: config.color,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: IconButton.filledTonal(
                        key: _syncKey,
                        onPressed: () => _syncData(context),
                        icon: const Icon(Icons.sync_rounded, size: 20),
                        tooltip: 'Sync Now',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(38, 38),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.75),
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (user != null)
                      InkWell(
                        key: _profileKey,
                        onTap: () => _openProfileAndMarkSeen(user),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16, left: 2),
                          child: Consumer(
                            builder: (context, ref, child) {
                              final requests = ref.watch(myJoinRequestsProvider).value ?? [];
                              final invites = ref.watch(myIncomingInvitationsProvider).value ?? [];
                              final pendingCount = requests.where((r) => r.request.status.toLowerCase() == 'pending').length + invites.length;
                              final displayBadgeCount = pendingCount > _unreadNotificationCount ? pendingCount : _unreadNotificationCount;

                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.25),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: config.color.withValues(alpha: 0.1),
                                      backgroundImage: user.avatarUrl != null
                                          ? NetworkImage(user.avatarUrl!)
                                          : null,
                                      child: user.avatarUrl == null
                                          ? Text(
                                              user.name.isNotEmpty
                                                  ? user.name[0].toUpperCase()
                                                  : 'U',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: config.color,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (displayBadgeCount > 0)
                                    Positioned(
                                      right: -5,
                                      top: -5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              width: 1),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Text(
                                          displayBadgeCount > 99
                                              ? '99+'
                                              : displayBadgeCount.toString(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(102),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () => showAppSearchSheet(context),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                height: 44,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search_rounded,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.62),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        'Search tours, events or profiles',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.7),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        TabBar(
                          key: _tabBarKey,
                          indicatorSize: TabBarIndicatorSize.label,
                          indicatorWeight: 3,
                          indicatorColor: config.color,
                          labelColor: config.color,
                          unselectedLabelColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                          labelStyle:
                              const TextStyle(fontWeight: FontWeight.bold),
                          tabs: [
                            const Tab(text: 'Activity Feed'),
                            Tab(text: config.pluralLabel),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                body: TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: () => _syncData(context),
                      child: _buildCentralFeed(context, config),
                    ),
                    RefreshIndicator(
                      onRefresh: () => _syncData(context),
                      child: _buildTourList(context, config, user),
                    ),
                  ],
                ),
                floatingActionButton: FloatingActionButton.extended(
                  key: _fabKey,
                  onPressed: () {
                    navigateWithTransition(context,
                        builder: () => const CreateTourScreen());
                  },
                  label: const Text('New',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  icon: const Icon(Icons.add_rounded),
                  backgroundColor: config.color,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(body: Center(child: Text("Error: $e"))),
    );
  }

  Widget _buildCentralFeed(BuildContext context, PurposeConfig config) {
    final activityAsync = ref.watch(globalActivityProvider);

    return activityAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off_rounded,
                    size: 80,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.1)),
                const SizedBox(height: 16),
                Text("No Recent Activity",
                    style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.3),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Search the app to find tours, events, or user profiles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _showJoinDialog(context, config),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Join with Code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: config.color,
                    side:
                        BorderSide(color: config.color.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return PremiumCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () {
                navigateWithTransition(context,
                    builder: () => TourDetailsScreen(
                        tourId: item.tour.id, tourName: item.tour.name));
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: config.color.withValues(alpha: 0.1),
                    backgroundImage: item.user?.avatarUrl != null
                        ? NetworkImage(item.user!.avatarUrl!)
                        : null,
                    child: (item.user?.avatarUrl == null)
                        ? Text(
                            item.user != null && item.user!.name.isNotEmpty
                                ? item.user!.name[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: config.color,
                                fontSize: 11))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            item.type == 'expense'
                                ? item.item.title
                                : (item.type == 'income'
                                    ? item.item.source
                                    : 'Settlement'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                            "${item.type == 'expense' ? 'Paid by' : 'By'} ${item.user?.name ?? 'Someone'} • ${item.tour.name}",
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(DateFormat('MMM dd, hh:mm a').format(item.date),
                            style: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Text("৳${item.amount.toStringAsFixed(0)}",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: item.type == 'expense'
                              ? Colors.redAccent
                              : Colors.green)),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildTourList(
      BuildContext context, PurposeConfig config, models.User? currentUser) {
    final toursAsync = ref.watch(tourListProvider);

    return toursAsync.when(
      data: (tours) {
        if (tours.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMyJoinRequestsSection(config),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: config.color.withValues(alpha: 0.05),
                          shape: BoxShape.circle),
                      child: Icon(config.icon,
                          size: 60, color: config.color.withValues(alpha: 0.3)),
                    ),
                    const SizedBox(height: 32),
                    Text("No ${config.pluralLabel} yet!",
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 12),
                    Text(
                        "Create a new ${config.label.toLowerCase()} or join an existing one with a code to start tracking expenses.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                            fontSize: 15,
                            height: 1.5)),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: () {
                          navigateWithTransition(context,
                              builder: () => const CreateTourScreen());
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: Text("Create New ${config.label}"),
                        style: FilledButton.styleFrom(
                          backgroundColor: config.color,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: () => _showJoinDialog(context, config),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text("Join with Code"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: config.color,
                          side: BorderSide(color: config.color, width: 2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          itemCount: tours.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _buildMyJoinRequestsSection(config);
            final tourWithRole = tours[index - 1];
            final tour = tourWithRole.tour;
            final role = tourWithRole.role;
            final tourConfig = PurposeConfig.getConfig(tour.purpose);

            return PremiumCard(
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TourDetailsScreen(
                            tourId: tour.id, tourName: tour.name)));
              },
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: tourConfig.gradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: tourConfig.color.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child:
                          Icon(tourConfig.icon, color: Colors.white, size: 22),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tour.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!tour.isSynced)
                          GestureDetector(
                            onTap: () async {
                              final db = ref.read(databaseProvider);
                              final isLocalOnly =
                                  await db.isTourLocalOnly(tour.id);
                              if (!mounted) return;

                              if (isLocalOnly) {
                                _showLocalOnlySyncHelp(tour);
                              } else {
                                _syncTourFromList();
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.orange
                                          .withValues(alpha: 0.3))),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_upload_outlined,
                                      color: Colors.orange, size: 10),
                                  SizedBox(width: 4),
                                  Text("LOCAL (সিঙ্ক করুন)",
                                      style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0)),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color:
                                        Colors.green.withValues(alpha: 0.3))),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_done_rounded,
                                    color: Colors.green, size: 10),
                                SizedBox(width: 4),
                                Text("CLOUD PROTECTED",
                                    style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 11, color: tourConfig.color),
                          const SizedBox(width: 4),
                          Text(
                            tour.startDate == null
                                ? "Active ${tourConfig.label}"
                                : DateFormat('MMM dd, yyyy')
                                    .format(tour.startDate!),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        if (value == 'edit') {
                          navigateWithTransition(context,
                              builder: () =>
                                  CreateTourScreen(initialTour: tour));
                        } else if (value == 'delete') {
                          _confirmDeleteTour(context, tour);
                        }
                      },
                      itemBuilder: (context) => [
                        if (role == 'admin' || role == 'editor')
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(children: [
                              Icon(Icons.edit_rounded, size: 18),
                              SizedBox(width: 12),
                              Text('Edit Details')
                            ]),
                          ),
                        if (role == 'admin')
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.red, size: 18),
                              SizedBox(width: 12),
                              Text('Remove', style: TextStyle(color: Colors.red))
                            ]),
                          ),
                        if (role != 'admin' && role != 'editor')
                           const PopupMenuItem(
                            enabled: false,
                            child: Text('Viewing Only', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: tourConfig.color.withValues(alpha: 0.05),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatIndicator(Icons.people_alt_rounded,
                            tourConfig.memberLabel, tourConfig.color),
                        _buildStatIndicator(Icons.payments_rounded,
                            tourConfig.expenseListLabel, tourConfig.color),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildStatIndicator(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7))),
      ],
    );
  }

  /// Shows a section with ALL pending/rejected join requests sent by the current
  /// user. Approved requests are omitted because the tour already appears in the
  /// main list. The section is a no-op (SizedBox.shrink) when there is nothing
  /// to show, so it does not disturb the layout.
  Widget _buildMyJoinRequestsSection(PurposeConfig config) {
    final myRequestsAsync = ref.watch(myJoinRequestsProvider);
    return myRequestsAsync.when(
      data: (all) {
        final visible = all
            .where((r) =>
                r.request.status == 'pending' ||
                r.request.status == 'rejected')
            .toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions_rounded,
                        size: 15,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      '\u0986\u09ae\u09be\u09b0 Join Requests',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              ...visible.map((jr) => _buildJoinRequestStatusCard(jr)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildJoinRequestStatusCard(JoinRequestWithTour jr) {
    final isPending = jr.request.status == 'pending';
    final tourName = jr.tour?.name ?? 'Unknown Tour';
    final tourPurpose = jr.tour?.purpose ?? 'tour';
    final jrTourConfig = PurposeConfig.getConfig(tourPurpose);

    final bgColor = isPending ? Colors.amber.shade50 : Colors.red.shade50;
    final borderColor =
        isPending ? Colors.amber.shade200 : Colors.red.shade200;
    final textColor =
        isPending ? Colors.amber.shade800 : Colors.red.shade800;
    final statusIcon =
        isPending ? Icons.hourglass_top_rounded : Icons.cancel_rounded;
    final statusLabel = isPending ? 'PENDING' : 'REJECTED';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: jrTourConfig.gradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Icon(jrTourConfig.icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tourName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isPending
                      ? 'Admin \u0985\u09a8\u09c1\u09ae\u09cb\u09a6\u09a8\u09c7\u09b0 \u0985\u09aa\u09c7\u0995\u09cd\u09b7\u09be\u09af\u09bc...'
                      : '\u0986\u09aa\u09a8\u09be\u09b0 request \u09aa\u09cd\u09b0\u09a4\u09cd\u09af\u09be\u0996\u09cd\u09af\u09be\u09a4 \u09b9\u09af\u09bc\u09c7\u099b\u09c7',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 10, color: textColor),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTour(BuildContext context, models.Tour tour) {
    final tourConfig = PurposeConfig.getConfig(tour.purpose);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Delete ${tourConfig.label}"),
        content: Text(
            "Are you sure you want to delete '${tour.name}'? This will delete all data associated with it."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () async {
                final db = ref.read(databaseProvider);
                await db.deleteTourWithDetails(tour.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${tourConfig.label} deleted")));
                }
              },
              child: const Text("Delete",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _syncData(BuildContext context) async {
    // Capture messenger BEFORE any async gaps to avoid context-across-gap warnings
    final messenger = ScaffoldMessenger.of(context);

    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    // ── Connectivity check before sync ──────────────────────────────────────
    final isOnline = await SyncHandler.isConnected();
    if (!isOnline) {
      if (mounted) {
        _showNoInternetSheet(
            context); // ignore: use_build_context_synchronously
      }
      return;
    }
    // ────────────────────────────────────────────────────────────────────────

    messenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 16),
            Text('ক্লাউডের সাথে সিঙ্ক হচ্ছে...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 15),
      ),
    );

    try {
      await ref.read(syncServiceProvider).startSync(user.id);
      await _refreshNotifications();

      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('সিঙ্ক সম্পন্ন হয়েছে! ✓'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
        ref.invalidate(tourListProvider);
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'সিঙ্ক ব্যর্থ: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'আবার চেষ্টা',
              textColor: Colors.white,
              onPressed: () => _syncData(context),
            ),
          ),
        );
      }
    }
  }

  void _showNoInternetSheet(BuildContext context) {
    NoInternetSheet.show(
      context,
      onRetry: () => _syncData(context),
      title: 'সিঙ্ক করা সম্ভব হচ্ছে না',
    );
  }

  Future<void> _syncTourFromList() => _syncData(context);

  void _showLocalOnlySyncHelp(models.Tour tour) {
    final tourConfig = PurposeConfig.getConfig(tour.purpose);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext)
                          .dividerColor
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.12),
                      child: const Icon(Icons.cloud_off_rounded,
                          color: Colors.orange),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Local Only ${tourConfig.label}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'To sync this ${tourConfig.label.toLowerCase()}, do these steps:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSyncStep('1',
                    'Open the edit screen for this ${tourConfig.label.toLowerCase()}.'),
                _buildSyncStep('2', 'Turn off the Local Only toggle.'),
                _buildSyncStep(
                    '3', 'Save the tour, then sync it to the cloud.'),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      navigateWithTransition(
                        context,
                        builder: () => CreateTourScreen(initialTour: tour),
                      );
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Open Edit Screen'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStep(String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              step,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context, PurposeConfig config) {
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Text(
                    'Join ${config.label}',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code shared by your host',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: controller,
                    enabled: !isLoading,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 32,
                        letterSpacing: 12,
                        fontWeight: FontWeight.bold,
                        color: config.color),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: 'CODE',
                      hintStyle: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.1),
                          letterSpacing: 4),
                      fillColor: config.color.withValues(alpha: 0.05),
                      filled: true,
                      counterText: "",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: config.color, width: 2),
                      ),
                      errorText: errorText,
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          child: IconButton(
                            icon: Icon(Icons.paste_rounded,
                                color: config.color, size: 20),
                            onPressed: isLoading
                                ? null
                                : () async {
                                    try {
                                      final clipboardData =
                                          await Clipboard.getData(
                                              Clipboard.kTextPlain);
                                      if (clipboardData != null &&
                                          clipboardData.text != null) {
                                        final pastedText = clipboardData.text!
                                            .replaceAll(
                                                RegExp(r'[^a-zA-Z0-9]'), '')
                                            .trim()
                                            .toUpperCase();
                                        if (pastedText.length == 6) {
                                          controller.text = pastedText;
                                          setState(() => errorText = null);
                                        } else {
                                          setState(() =>
                                              errorText = "Invalid format");
                                        }
                                      }
                                    } catch (e) {
                                      setState(
                                          () => errorText = "Failed to paste");
                                    }
                                  },
                          ),
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      if (errorText != null) setState(() => errorText = null);
                    },
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 60,
                    child: FilledButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              final code = controller.text
                                  .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                                  .trim()
                                  .toUpperCase();
                              if (code.length != 6) {
                                setState(() => errorText = "6 digits required");
                                return;
                              }

                              setState(() {
                                isLoading = true;
                                errorText = null;
                              });

                              try {
                                final user =
                                    await ref.read(currentUserProvider.future);
                                if (user == null) return;

                                final tourRes = await ref
                                    .read(syncServiceProvider)
                                    .findTourByCode(code);
                                if (tourRes == null) {
                                  setState(() => errorText =
                                      "Not found. Ask host to sync.");
                                  return;
                                }

                                if (context.mounted) {
                                  final proceed = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text("${config.label} Found!"),
                                      content: Text(
                                          "Do you want to join '${tourRes['name']}'?"),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text("Cancel")),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text("Join Now")),
                                      ],
                                    ),
                                  );

                                  if (proceed == true) {
                                    await ref
                                        .read(syncServiceProvider)
                                        .joinByInvite(
                                          code,
                                          user.id,
                                          user.name,
                                          email: user.email,
                                          avatarUrl: user.avatarUrl,
                                          purpose: user.purpose,
                                        );
                                    ref.invalidate(tourListProvider);
                                    if (context.mounted) Navigator.pop(context);
                                  }
                                }
                              } catch (e) {
                                String msg = e.toString().contains("403")
                                    ? "Request Needed"
                                    : e.toString();
                                if (msg.contains("Request Needed")) {
                                  if (!mounted) return;
                                  final tourRes = await ref
                                      .read(syncServiceProvider)
                                      .findTourByCode(code);
                                  if (tourRes != null) {
                                    final req = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title:
                                            Text("Restricted ${config.label}"),
                                        content: Text(
                                            "'${tourRes['name']}' is private. Send a join request?"),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text("No")),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child:
                                                  const Text("Send Request")),
                                        ],
                                      ),
                                    );
                                    if (req == true) {
                                      await ref
                                          .read(syncServiceProvider)
                                          .requestToJoin(tourRes['id']);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  "Request sent to Admin")));
                                      Navigator.pop(context);
                                    }
                                  }
                                } else {
                                  setState(() => errorText =
                                      msg.replaceAll("Exception:", "").trim());
                                }
                              } finally {
                                if (mounted) setState(() => isLoading = false);
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: config.color,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3))
                          : const Text('Join Team Now',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
