import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/data/providers/app_providers.dart';

import '../../data/local/app_database.dart' as models;
import '../../domain/logic/purpose_config.dart';
import '../screens/tour_details_screen.dart';
import '../screens/user_profile_screen.dart';
import 'smooth_page_transition.dart';

void showAppSearchSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AppSearchSheet(),
  );
}

class AppSearchSheet extends ConsumerStatefulWidget {
  const AppSearchSheet({super.key});

  @override
  ConsumerState<AppSearchSheet> createState() => _AppSearchSheetState();
}

class _AppSearchSheetState extends ConsumerState<AppSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _isLoading = false;
  String _query = '';
  List<models.Tour> _tourResults = [];
  List<models.User> _userResults = [];
  Set<String> _joinedTourIds = <String>{};
  Set<String> _pendingTourIds = <String>{};

  @override
  void initState() {
    super.initState();
    _primeMembershipState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _primeMembershipState() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    final db = ref.read(databaseProvider);
    final activeMemberships = await (db.select(db.tourMembers)
          ..where((m) =>
              m.userId.equals(currentUser.id) & m.status.equals('active')))
        .get();
    final pendingRequests = await (db.select(db.joinRequests)
          ..where((jr) =>
              jr.userId.equals(currentUser.id) & jr.status.equals('pending')))
        .get();

    if (!mounted) return;
    setState(() {
      _joinedTourIds = activeMemberships.map((m) => m.tourId).toSet();
      _pendingTourIds = pendingRequests.map((r) => r.tourId).toSet();
    });
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _search(value);
    });
  }

  Future<void> _search(String rawQuery) async {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _query = '';
        _tourResults = [];
        _userResults = [];
        _isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _query = query;
      _isLoading = true;
    });

    // Use Future.delayed to prevent rebuild conflicts
    await Future.delayed(Duration.zero);

    try {
      final db = ref.read(databaseProvider);

      // Fetch all non-deleted tours
      final allTours = await (db.select(db.tours)
            ..where((t) => t.isDeleted.equals(false)))
          .get();

      // Filter in memory with null-safety
      final filteredTours = <models.Tour>[];
      for (final tour in allTours) {
        try {
          final name = tour.name;
          final purpose = tour.purpose;
          if (name.toLowerCase().contains(query) ||
              purpose.toLowerCase().contains(query)) {
            filteredTours.add(tour);
          }
        } catch (e) {
          debugPrint('⚠️ Error filtering tour: $e');
          continue;
        }
      }
      filteredTours.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      // Fetch all non-deleted users
      final allUsers = await (db.select(db.users)
            ..where((u) => u.isDeleted.equals(false)))
          .get();

      // Filter in memory with null-safety
      final filteredUsers = <models.User>[];
      for (final user in allUsers) {
        try {
          final name = user.name;
          if (name.toLowerCase().contains(query)) {
            filteredUsers.add(user);
          }
        } catch (e) {
          debugPrint('⚠️ Error filtering user: $e');
          continue;
        }
      }
      filteredUsers.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      if (!mounted) return;
      setState(() {
        _tourResults = filteredTours;
        _userResults = filteredUsers;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('❌ Search Error: $e\n$st');
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        final errorMsg = e.toString().split('\n').first;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _requestJoin(models.Tour tour) async {
    try {
      await ref.read(syncServiceProvider).requestToJoin(tour.id);
      await _primeMembershipState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join request sent for ${tour.name}')),
      );
      await _search(_searchController.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Request failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _openTour(models.Tour tour) {
    Navigator.pop(context);
    navigateWithTransition(
      context,
      builder: () => TourDetailsScreen(tourId: tour.id, tourName: tour.name),
    );
  }

  void _openUser(models.User user) {
    Navigator.pop(context);
    navigateWithTransitionFromRight(
      context,
      builder: () => UserProfileScreen(user: user, isMe: user.isMe),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    final config = PurposeConfig.getConfig(currentUser?.purpose);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.65,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.search_rounded, color: config.color),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Search tours, events, and profiles',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Type tour, event, or user name',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _query.isEmpty
                      ? Center(
                          child: Text(
                            'Search an existing tour or profile to open it or send a join request.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        )
                      : _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              controller: scrollController,
                              children: [
                                _buildSectionHeader('Tours / Events'),
                                if (_tourResults.isEmpty)
                                  _buildEmptyState('No tours or events found')
                                else
                                  ..._tourResults.map(_buildTourCard),
                                const SizedBox(height: 18),
                                _buildSectionHeader('Profiles'),
                                if (_userResults.isEmpty)
                                  _buildEmptyState('No profiles found')
                                else
                                  ..._userResults.map(_buildUserCard),
                              ],
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.4),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.55)),
      ),
    );
  }

  Widget _buildTourCard(models.Tour tour) {
    try {
      final config = PurposeConfig.getConfig(tour.purpose);
      final isJoined = _joinedTourIds.contains(tour.id);
      final isPending = _pendingTourIds.contains(tour.id);
      final tourName = tour.name;
      final tourPurpose = tour.purpose;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.12)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: config.color.withValues(alpha: 0.12),
              child: Icon(config.icon, color: config.color),
            ),
            title: Text(tourName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${config.label} • $tourPurpose',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: isJoined
                ? SizedBox(
                    width: 70,
                    child: FilledButton(
                      onPressed: () => _openTour(tour),
                      child: const Text('Open'),
                    ),
                  )
                : isPending
                    ? const SizedBox(
                        width: 70,
                        child: Chip(label: Text('Pending')),
                      )
                    : SizedBox(
                        width: 95,
                        child: FilledButton(
                          onPressed: () => _requestJoin(tour),
                          child: const Text('Request Join'),
                        ),
                      ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error building tour card: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildUserCard(models.User user) {
    try {
      final isMe = user.id == ref.read(currentUserProvider).value?.id;
      final avatarImage = _resolveAvatarImage(user.avatarUrl);
      final userName = user.name;
      final userSubtitle = isMe
          ? 'My profile'
          : ((user.email ?? '').isNotEmpty
              ? user.email!
              : ((user.phone ?? '').isNotEmpty ? user.phone! : 'Profile'));

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.12)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: CircleAvatar(
              backgroundImage: avatarImage,
              child: avatarImage == null
                  ? Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )
                  : null,
            ),
            title: Text(userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(userSubtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: SizedBox(
              width: 65,
              child: FilledButton(
                onPressed: () => _openUser(user),
                child: Text(isMe ? 'Open Me' : 'Open'),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error building user card: $e');
      return const SizedBox.shrink();
    }
  }

  ImageProvider? _resolveAvatarImage(String? rawValue) {
    if (rawValue == null) return null;
    final value = rawValue.trim();
    if (value.isEmpty) return null;

    try {
      if (value.startsWith('data:image')) {
        final parts = value.split(',');
        if (parts.length > 1 && parts.last.isNotEmpty) {
          return MemoryImage(base64Decode(parts.last));
        }
        return null;
      }

      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
      if (!isHttp) return null;
      return NetworkImage(value);
    } catch (_) {
      return null;
    }
  }
}
