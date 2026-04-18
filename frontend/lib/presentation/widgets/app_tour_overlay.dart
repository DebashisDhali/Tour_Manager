import 'package:flutter/material.dart';
import 'dart:math';

/// A single step in the app tour
class TourStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final TooltipPosition position;

  const TourStep({
    required this.targetKey,
    required this.title,
    required this.description,
    required this.icon,
    this.accentColor = const Color(0xFF6366F1),
    this.position = TooltipPosition.below,
  });
}

enum TooltipPosition { above, below, left, right }

/// The main App Tour overlay widget
class AppTourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final VoidCallback onComplete;
  final Widget child;

  const AppTourOverlay({
    super.key,
    required this.steps,
    required this.onComplete,
    required this.child,
  });

  @override
  State<AppTourOverlay> createState() => AppTourOverlayState();
}

class AppTourOverlayState extends State<AppTourOverlay>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  bool _isActive = false;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  /// Start the tour programmatically
  void startTour() {
    setState(() {
      _currentStep = 0;
      _isActive = true;
    });
    _fadeController.forward(from: 0);
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      _fadeController.reverse().then((_) {
        setState(() => _currentStep++);
        _fadeController.forward(from: 0);
      });
    } else {
      _endTour();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _fadeController.reverse().then((_) {
        setState(() => _currentStep--);
        _fadeController.forward(from: 0);
      });
    }
  }

  void _endTour() {
    _fadeController.reverse().then((_) {
      setState(() => _isActive = false);
      widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isActive) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final step = widget.steps[_currentStep];
    final targetContext = step.targetKey.currentContext;

    // If key not found, show a generic center tooltip
    Rect? targetRect;
    if (targetContext != null) {
      final RenderBox box = targetContext.findRenderObject() as RenderBox;
      final offset = box.localToGlobal(Offset.zero);
      targetRect = Rect.fromLTWH(
        offset.dx,
        offset.dy,
        box.size.width,
        box.size.height,
      );
    }

    final screenSize = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Dark overlay with spotlight cutout
            GestureDetector(
              onTap: () {}, // Absorb taps
              child: CustomPaint(
                size: screenSize,
                painter: _SpotlightPainter(
                  targetRect: targetRect,
                  pulseAnimation: _pulseAnim,
                  accentColor: step.accentColor,
                ),
              ),
            ),

            // Tooltip card
            if (targetRect != null)
              _buildPositionedTooltip(step, targetRect, screenSize)
            else
              _buildCenteredTooltip(step, screenSize),

            // Step counter at top
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              right: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Step indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tour_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Step ${_currentStep + 1} of ${widget.steps.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Skip button
                  GestureDetector(
                    onTap: _endTour,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Skip Tour',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Progress dots at bottom
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.steps.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _currentStep ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _currentStep
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionedTooltip(TourStep step, Rect target, Size screenSize) {
    // Determine the best position for the tooltip
    final double tooltipMaxWidth = screenSize.width - 48;
    final bool showBelow = target.center.dy < screenSize.height * 0.5;

    double top;
    if (showBelow) {
      top = target.bottom + 20;
    } else {
      top = max(target.top - 220, MediaQuery.of(context).padding.top + 70);
    }

    return Positioned(
      top: top,
      left: 24,
      right: 24,
      child: _buildTooltipCard(step, tooltipMaxWidth),
    );
  }

  Widget _buildCenteredTooltip(TourStep step, Size screenSize) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: _buildTooltipCard(step, screenSize.width - 48),
      ),
    );
  }

  Widget _buildTooltipCard(TourStep step, double maxWidth) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: step.accentColor.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colored accent header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  step.accentColor,
                  step.accentColor.withValues(alpha: 0.8),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(step.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Description
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              step.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withValues(alpha: 0.65),
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Navigation row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0)
                  TextButton.icon(
                    onPressed: _prevStep,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black45,
                    ),
                  )
                else
                  const SizedBox(),
                FilledButton(
                  onPressed: _nextStep,
                  style: FilledButton.styleFrom(
                    backgroundColor: step.accentColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentStep == widget.steps.length - 1
                            ? "Let's Go!"
                            : 'Next',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _currentStep == widget.steps.length - 1
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Spotlight Painter ────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Animation<double> pulseAnimation;
  final Color accentColor;

  _SpotlightPainter({
    this.targetRect,
    required this.pulseAnimation,
    required this.accentColor,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    if (targetRect == null) {
      // Semi-transparent dark overlay for the whole screen
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xCC0F172A));
      return;
    }

    final pulse = pulseAnimation.value;
    final expandedRect = targetRect!.inflate(8 + pulse);
    final radius = Radius.circular(16);

    // Create a new layer to handle blending correctly
    canvas.saveLayer(Offset.zero & size, Paint());

    // 1. Draw the dark overlay on the entire screen
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xCC0F172A));

    // 2. Cut out the hole for the spotlight using BlendMode.clear
    final holeRRect = RRect.fromRectAndRadius(expandedRect, radius);
    canvas.drawRRect(holeRRect, Paint()..blendMode = BlendMode.clear);

    // 3. Draw a VERY slight tint inside the hole to make it feel special (optional premium touch)
    canvas.drawRRect(
        holeRRect, Paint()..color = accentColor.withValues(alpha: 0.05));

    canvas.restore();

    // 4. Glowing border around target
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.6 - pulse * 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
    canvas.drawRRect(holeRRect, glowPaint);

    // 5. Solid sharp border
    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(holeRRect, borderPaint);

    // 6. Optional: Subtle inner glow to guide the eye
    final innerGlowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(holeRRect.deflate(2), innerGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => true;
}
