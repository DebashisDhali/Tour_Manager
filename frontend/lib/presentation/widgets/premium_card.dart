import 'package:flutter/material.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Gradient? gradient;
  final Color? shadowColor;
  final double borderRadius;
  final double elevation;
  final VoidCallback? onTap;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.gradient,
    this.shadowColor,
    this.borderRadius = 24.0,
    this.elevation = 0.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Theme.of(context).cardColor) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: elevation > 0 ? [
          BoxShadow(
            color: shadowColor ?? (Theme.of(context).brightness == Brightness.dark 
                ? Colors.black.withOpacity(0.4) 
                : Colors.black.withOpacity(0.04)),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}
