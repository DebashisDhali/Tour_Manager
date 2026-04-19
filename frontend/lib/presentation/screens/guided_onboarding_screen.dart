import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_screen.dart';

class GuidedOnboardingScreen extends StatefulWidget {
  const GuidedOnboardingScreen({super.key});

  @override
  State<GuidedOnboardingScreen> createState() => _GuidedOnboardingScreenState();
}

class _GuidedOnboardingScreenState extends State<GuidedOnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<_GuideStep> _steps = [
    _GuideStep(
      title: 'স্বাগতম ট্যুর কস্ট ম্যানেজারে! 👋',
      description:
          'এই অ্যাপটি আপনার সব ট্যুর, ভ্রমণ, মেস এবং গ্রুপ খরচ সহজে হিসাব করে দেয়।',
      tips: [
        '📱 সবাই এক্সেস করতে পারে এক জায়গা থেকে',
        '💡 কোনো ক্যালকুলেটর বা খাতার দরকার নেই',
        '⚡ অনলাইন বা অফলাইন - দুটোতেই কাজ করে',
      ],
      icon: Icons.tour_rounded,
      color: const Color(0xFF6366F1),
    ),
    _GuideStep(
      title: 'প্রথম স্টেপ: ট্যুর/গ্রুপ তৈরি করুন ✏️',
      description: 'নতুন ট্যুর তৈরি করতে "নতুন ট্যুর" বাটন ক্লিক করুন।',
      tips: [
        '📛 ট্যুরের নাম লিখুন (যেমন: "ঢাকা ট্রিপ")',
        '📅 শুরু এবং শেষ তারিখ বেছে নিন',
        '👥 বন্ধুদের নাম যোগ করুন বা পরে যোগ করতে পারেন',
        '✅ সেভ করুন এবং শেষ!',
      ],
      icon: Icons.add_circle_rounded,
      color: const Color(0xFF10B981),
    ),
    _GuideStep(
      title: 'খরচ যোগ করুন এবং ভাগ করুন 💰',
      description: 'কোনো খরচ হয়েছে? এটা সরাসরি অ্যাপে যোগ করুন।',
      tips: [
        '💵 খরচের পরিমাণ লিখুন',
        '👤 কে খরচ করেছে তা নির্বাচন করুন',
        '👥 কাদের মধ্যে ভাগ হবে সেটা চয়ন করুন',
        '🧮 অ্যাপ আপনার জন্য হিসাব করবে!',
      ],
      icon: Icons.receipt_rounded,
      color: const Color(0xFF0EA5E9),
    ),
    _GuideStep(
      title: 'অন্যদের সাথে যোগ দিন 🤝',
      description: 'বন্ধুদের আপনার ট্যুরে যোগ করতে একটি কোড শেয়ার করুন।',
      tips: [
        '🔗 আপনার ট্যুরে একটি ইনভাইট কোড জেনারেট হয়',
        '📤 এই 6-digit কোডটি বন্ধুদের সাথে শেয়ার করুন',
        '📲 তারা কোড দিয়ে যোগ দিতে পারবে',
        '✔️ সবাই এক সাথে খরচ ট্র্যাক করতে পারবে',
      ],
      icon: Icons.group_add_rounded,
      color: const Color(0xFFF59E0B),
    ),
    _GuideStep(
      title: 'সেটেলমেন্ট (শেষ হিসাব) 📊',
      description: 'ট্যুর শেষে কে কাকে কত টাকা দেবে এটা অটোম্যাটিক দেখবে।',
      tips: [
        '🎯 সব খরচের সামঞ্জস্য (settlement) হিসাব হয় স্বয়ংক্রিয়',
        '🔢 ন্যূনতম লেনদেন দিয়ে সবাই সামান্য করতে পারে',
        '📋 বিস্তারিত রিপোর্ট দেখতে পারবেন',
        '✨ সবার জন্য ন্যায্য এবং স্বচ্ছ হিসাব',
      ],
      icon: Icons.bar_chart_rounded,
      color: const Color(0xFF8B5CF6),
    ),
    _GuideStep(
      title: 'প্রো টিপস 🎯',
      description: 'সবচেয়ে কার্যকরভাবে অ্যাপ ব্যবহার করার উপায়।',
      tips: [
        '📱 সিঙ্ক বাটন দিয়ে সবসময় আপডেট থাকুন',
        '⚙️ প্রোফাইল থেকে সেটিংস পরিবর্তন করতে পারেন',
        '❓ যেকোনো সময় প্রোফাইল থেকে সাহায্য পেতে পারেন',
        '💡 শিখতে থাকুন - আমরা নতুন ফিচার যোগ করছি!',
      ],
      icon: Icons.lightbulb_rounded,
      color: const Color(0xFF06B6D4),
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
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
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
          pageBuilder: (_, __, ___) => const RegisterScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentPage];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / _steps.length,
                  minHeight: 6,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(step.color),
                ),
              ),
            ),

            // Main content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final s = _steps[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon
                        Center(
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: s.color.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                s.icon,
                                size: 64,
                                color: s.color,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Title
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: Text(
                              s.title,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Description
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: Text(
                            s.description,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Tips
                        ...s.tips.map((tip) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: s.color,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      tip,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Previous button
                  if (_currentPage > 0)
                    TextButton.icon(
                      onPressed: _previousPage,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('পিছনে'),
                    )
                  else
                    const SizedBox(width: 80),

                  // Page counter
                  Text(
                    '${_currentPage + 1}/${_steps.length}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  // Next/Finish button
                  FilledButton.icon(
                    onPressed: _nextPage,
                    icon: Icon(_currentPage == _steps.length - 1
                        ? Icons.check
                        : Icons.arrow_forward),
                    label: Text(_currentPage == _steps.length - 1
                        ? 'শুরু করুন'
                        : 'পরবর্তী'),
                  ),
                ],
              ),
            ),

            // Skip button
            if (_currentPage < _steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: const Text('স্কিপ করুন'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep {
  final String title;
  final String description;
  final List<String> tips;
  final IconData icon;
  final Color color;

  _GuideStep({
    required this.title,
    required this.description,
    required this.tips,
    required this.icon,
    required this.color,
  });
}
