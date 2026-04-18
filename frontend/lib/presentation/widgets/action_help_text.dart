import 'package:flutter/material.dart';

class ActionHelpText extends StatelessWidget {
  final String message;
  const ActionHelpText(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          height: 1.4,
        ),
      ),
    );
  }
}
