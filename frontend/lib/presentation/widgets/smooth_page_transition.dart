import 'package:flutter/material.dart';

/// Custom page transitions with smooth animations
class SmoothPageTransition extends PageRouteBuilder {
  final Widget page;
  final Duration duration;
  final Curve curve;

  SmoothPageTransition({
    required this.page,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeInOutCubic,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade + slide up transition
            const begin = Offset(0.0, 0.1);
            const end = Offset.zero;
            final tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );

            return FadeTransition(
              opacity: animation.drive(
                Tween(begin: 0.0, end: 1.0).chain(
                  CurveTween(curve: curve),
                ),
              ),
              child: SlideTransition(
                position: animation.drive(tween),
                child: ScaleTransition(
                  scale: animation.drive(
                    Tween(begin: 0.95, end: 1.0).chain(
                      CurveTween(curve: curve),
                    ),
                  ),
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Quick helper to navigate with smooth transition
void navigateWithTransition(
  BuildContext context, {
  required Widget Function() builder,
  bool replace = false,
}) {
  final route = SmoothPageTransition(page: builder());
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

/// Quick helper for replace and remove all
void navigateWithTransitionResetStack(
  BuildContext context, {
  required Widget Function() builder,
}) {
  final route = SmoothPageTransition(page: builder());
  Navigator.of(context).pushAndRemoveUntil(
    route,
    (route) => false,
  );
}
