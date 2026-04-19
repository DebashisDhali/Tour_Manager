import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/providers/theme_provider.dart';
import 'data/providers/app_providers.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/guided_onboarding_screen.dart';
import 'presentation/screens/tour_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MyApp(prefs: prefs),
    ),
  );
}

class MyApp extends ConsumerWidget {
  final SharedPreferences prefs;

  const MyApp({required this.prefs, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tour Cost Manager',
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: _HomeRouter(prefs: prefs),
    );
  }
}

class _HomeRouter extends StatefulWidget {
  final SharedPreferences prefs;

  const _HomeRouter({required this.prefs});

  @override
  State<_HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<_HomeRouter> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final done = widget.prefs.getBool('onboarding_done') ?? false;
      if (mounted) {
        setState(() => _showOnboarding = !done);
      }
    } catch (e) {
      debugPrint('Error checking onboarding: $e');
      if (mounted) {
        setState(() => _showOnboarding = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing...'),
            ],
          ),
        ),
      );
    }

    if (_showOnboarding!) {
      return const GuidedOnboardingScreen();
    }

    // Check for auto-login
    return _AutoLoginWrapper(child: const LoginScreen());
  }
}

class _AutoLoginWrapper extends ConsumerWidget {
  final Widget child;

  const _AutoLoginWrapper({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(authServiceProvider).restoreSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Restoring session...'),
                ],
              ),
            ),
          );
        }

        // If user session restored, go to TourListScreen
        if (snapshot.hasData && snapshot.data != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('✅ Auto-login successful: ${snapshot.data?.name}');
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const TourListScreen()),
              (route) => false,
            );
          });
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading app...'),
                ],
              ),
            ),
          );
        }

        // Otherwise, show login screen
        return child;
      },
    );
  }
}
