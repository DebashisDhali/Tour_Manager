import 'package:flutter/material.dart';

class NoInternetSheet extends StatelessWidget {
  final VoidCallback onRetry;
  final String? title;
  final String? message;
  final String? buttonLabel;
  final String? dismissLabel;

  const NoInternetSheet({
    super.key,
    required this.onRetry,
    this.title,
    this.message,
    this.buttonLabel,
    this.dismissLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 32),

          // Illustration
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 24),

          // Text
          Text(
            title ?? 'No Connection',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message ??
                'আপনার ইন্টারনেট কানেকশনটি চেক করুন এবং আবার চেষ্টা করুন।',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 15,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Retry button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                buttonLabel ?? 'Try Again',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Dismiss
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              child: Text(dismissLabel ?? 'Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  static void show(BuildContext context,
      {required VoidCallback onRetry, String? title, String? message}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoInternetSheet(
        onRetry: onRetry,
        title: title,
        message: message,
      ),
    );
  }
}
