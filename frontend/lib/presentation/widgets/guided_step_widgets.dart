import 'package:flutter/material.dart';

/// Widget for guided step-by-step process with help text
class GuidedStep extends StatelessWidget {
  final String title;
  final String? helpText;
  final String? example;
  final Widget child;
  final bool isRequired;

  const GuidedStep({
    required this.title,
    this.helpText,
    this.example,
    required this.child,
    this.isRequired = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (helpText != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              border: Border.left(
                  side: BorderSide(
                      color: Colors.blue.withOpacity(0.3), width: 3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              helpText!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        const SizedBox(height: 10),
        child,
        if (example != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'উদাহরণ: $example',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Inline instruction widget
class InlineInstruction extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;

  const InlineInstruction({
    required this.text,
    this.icon = Icons.info_outline,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (color ?? Colors.amber).withOpacity(0.1),
        border: Border.all(color: (color ?? Colors.amber).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step progress indicator
class StepProgressIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> stepLabels;

  const StepProgressIndicator({
    required this.currentStep,
    required this.totalSteps,
    required this.stepLabels,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ধাপ $currentStep / $totalSteps',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            Text(
              stepLabels[currentStep - 1],
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: currentStep / totalSteps,
            minHeight: 6,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        ),
      ],
    );
  }
}

/// Help dialog for quick tips
class QuickTipDialog extends StatelessWidget {
  final String title;
  final String message;
  final List<String>? tips;

  const QuickTipDialog({
    required this.title,
    required this.message,
    this.tips,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    List<String>? tips,
  }) {
    return showDialog(
      context: context,
      builder: (context) => QuickTipDialog(
        title: title,
        message: message,
        tips: tips,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: Colors.orange, size: 24),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            if (tips != null && tips!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'টিপস:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...tips!.map((tip) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(tip)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('বুঝেছি'),
        ),
      ],
    );
  }
}
