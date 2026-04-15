import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_providers.dart';

class SyncHandler extends ConsumerStatefulWidget {
  final Widget child;
  const SyncHandler({super.key, required this.child});

  @override
  ConsumerState<SyncHandler> createState() => _SyncHandlerState();

  /// Lightweight connectivity check — attempts a DNS lookup for google.com.
  /// Returns true if the device is online, false otherwise.
  static Future<bool> isConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}

class _SyncHandlerState extends ConsumerState<SyncHandler>
    with WidgetsBindingObserver {
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

    // Auto-sync whenever unsynced changes are detected
    ref.listenManual(hasUnsyncedChangesProvider, (prev, next) {
      if (next.value == true) {
        // Debounce slightly to avoid rapid syncs when adding multiple things
        _debounceSync('Local Changes Detected');
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
    if (state == AppLifecycleState.resumed) {
      _triggerSync('App Resumed');
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _triggerSync('Periodic Sync');
    });
    Future.delayed(
        const Duration(seconds: 3), () => _triggerSync('Initial Sync'));
  }

  Timer? _debounceTimer;
  void _debounceSync(String reason) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _triggerSync(reason);
    });
  }

  Future<void> _triggerSync(String reason) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    // ── Connectivity guard ──────────────────────────────────────────────────
    final online = await SyncHandler.isConnected();
    if (!online) {
      debugPrint(
          '[SyncHandler] Skipping "$reason" — device appears to be offline.');
      return;
    }
    // ───────────────────────────────────────────────────────────────────────

    debugPrint('[SyncHandler] Triggering "$reason" for user ${user.name}');
    try {
      await ref.read(syncServiceProvider).startSync(user.id);
    } catch (e) {
      debugPrint('[SyncHandler] Sync failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
