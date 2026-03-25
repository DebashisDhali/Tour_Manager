import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_providers.dart';

class SyncHandler extends ConsumerStatefulWidget {
  final Widget child;
  const SyncHandler({super.key, required this.child});

  @override
  ConsumerState<SyncHandler> createState() => _SyncHandlerState();
}

class _SyncHandlerState extends ConsumerState<SyncHandler> with WidgetsBindingObserver {
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Auto-sync whenever currentUser is loaded or changes
    ref.listenManual(currentUserProvider, (prev, next) {
      if (next.value != null && prev?.value == null) {
        _triggerSync('User Logged In/Loaded');
      }
    });

    _startPeriodicSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Trigger sync when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      _triggerSync('App Resumed');
    }
  }

  void _startPeriodicSync() {
    // Sync every 5 minutes while active
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _triggerSync('Periodic Sync');
    });
    
    // Initial sync after 3 seconds
    Future.delayed(const Duration(seconds: 3), () => _triggerSync('Initial Sync'));
  }

  Future<void> _triggerSync(String reason) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    debugPrint("[SyncHandler] Triggering $reason for user ${user.name}");
    try {
      await ref.read(syncServiceProvider).startSync(user.id);
    } catch (e) {
      debugPrint("[SyncHandler] Sync failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
