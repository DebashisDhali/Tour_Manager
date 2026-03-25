import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<_OnboardingData> _pages = [
    _OnboardingData(
      image: 'assets/images/onboarding_1.png',
      badge: '🗺️  Start Exploring',
      title: 'Plan Every\nAdventure',
      subtitle:
          'Create tours, trips, and group events with ease. Track everything from one place — no spreadsheets needed.',
      gradientColors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      indicatorColor: Color(0xFF6366F1),
    ),
    _OnboardingData(
      image: 'assets/images/onboarding_2.png',
      badge: '💰  Smart Splits',
      title: 'Split Costs\nInstantly',
      subtitle:
          'Add expenses in seconds. The app auto-calculates who owes what — so nobody gets stuck with the bill.',
      gradientColors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
      indicatorColor: Color(0xFF0EA5E9),
    ),
    _OnboardingData(
      image: 'assets/images/onboarding_3.png',
      badge: '🤝  Stay In Sync',
      title: 'Collaborate With\nYour Team',
      subtitle:
          'Invite friends with a 6-digit code. Everyone stays updated in real-time — wherever you are.',
      gradientColors: [Color(0xFF10B981), Color(0xFF0EA5E9)],
      indicatorColor: Color(0xFF10B981),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _fadeController.reset();
    _slideController.reset();
    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => const WelcomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: page.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top row: skip button
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Page counter
                    Text(
                      '${_currentPage + 1} / ${_pages.length}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                    if (_currentPage < _pages.length - 1)
                      GestureDetector(
                        onTap: _completeOnboarding,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Illustration
              Expanded(
                flex: 5,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _IllustrationCard(
                        imagePath: _pages[index].image,
                        isActive: index == _currentPage,
                      ),
                    );
                  },
                ),
              ),

              // Bottom content card
              Expanded(
                flex: 4,
                child: Container(
                  margin: const EdgeInsets.only(top: 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(40)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: page.indicatorColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                page.badge,
                                style: TextStyle(
                                    color: page.indicatorColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Title
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: Text(
                              page.title,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                color: Color(0xFF0F172A),
                                height: 1.15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Subtitle
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: Text(
                            page.subtitle,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black.withOpacity(0.55),
                              height: 1.6,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Dots + Next button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Dots
                            Row(
                              children: List.generate(
                                _pages.length,
                                (i) => AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 350),
                                  margin:
                                      const EdgeInsets.only(right: 8),
                                  width: i == _currentPage ? 24 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: i == _currentPage
                                        ? page.indicatorColor
                                        : page.indicatorColor
                                            .withOpacity(0.2),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),

                            // Next / Get Started button
                            GestureDetector(
                              onTap: _nextPage,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      _currentPage == _pages.length - 1
                                          ? 24
                                          : 20,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: page.gradientColors),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: page.indicatorColor
                                          .withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    )
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _currentPage == _pages.length - 1
                                          ? 'Get Started'
                                          : 'Next',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Illustration Card ───────────────────────────────────────────────────────

class _IllustrationCard extends StatelessWidget {
  final String imagePath;
  final bool isActive;

  const _IllustrationCard({required this.imagePath, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isActive ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Image.asset(
            imagePath,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

// ─── Data Model ──────────────────────────────────────────────────────────────

class _OnboardingData {
  final String image;
  final String badge;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final Color indicatorColor;

  const _OnboardingData({
    required this.image,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.indicatorColor,
  });
}
