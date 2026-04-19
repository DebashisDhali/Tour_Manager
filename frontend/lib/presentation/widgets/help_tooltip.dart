import 'package:flutter/material.dart';

class HelpTooltip extends StatefulWidget {
  final String message;
  final Widget child;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final Duration duration;

  const HelpTooltip({
    required this.message,
    required this.child,
    this.backgroundColor,
    this.textStyle,
    this.duration = const Duration(seconds: 4),
    super.key,
  });

  @override
  State<HelpTooltip> createState() => _HelpTooltipState();
}

class _HelpTooltipState extends State<HelpTooltip> {
  late final OverlayPortalController _tooltipController;

  @override
  void initState() {
    super.initState();
    _tooltipController = OverlayPortalController();
  }

  void _show() {
    _tooltipController.show();
    Future.delayed(widget.duration, _tooltipController.hide);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _tooltipController,
      overlayChildBuilder: (BuildContext context) {
        return Positioned(
          bottom: 60,
          left: 20,
          right: 20,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.backgroundColor ?? Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: widget.textStyle ??
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ),
        );
      },
      child: GestureDetector(
        onLongPress: _show,
        child: Tooltip(
          message: 'Long press for help',
          child: widget.child,
        ),
      ),
    );
  }
}

/// Simple help button widget
class HelpButton extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback? onPressed;

  const HelpButton({
    required this.title,
    required this.content,
    this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline_rounded, size: 20),
      onPressed: onPressed ?? () => _showHelpDialog(context, title, content),
      tooltip: 'Help',
    );
  }

  static void _showHelpDialog(
      BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.blue),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Info Card with gradient background
class InfoCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color? color;

  const InfoCard({
    required this.title,
    required this.description,
    required this.icon,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (color ?? Colors.blue).withOpacity(0.1),
            (color ?? Colors.blue).withOpacity(0.05),
          ],
        ),
        border: Border.all(
          color: (color ?? Colors.blue).withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
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
