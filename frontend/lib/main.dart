import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/providers/theme_provider.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/onboarding_screen.dart';

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
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    try {
      final done = widget.prefs.getBool('onboarding_done') ?? false;
      if (mounted) {
        setState(() => _showOnboarding = !done);
      }
    } catch (e) {
      debugPrint('Error checking onboarding: $e');
      if (mounted) {
        setState(
            () => _showOnboarding = true); // Default to onboarding on error
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

    return _showOnboarding! ? const OnboardingScreen() : const LoginScreen();
  }
}
