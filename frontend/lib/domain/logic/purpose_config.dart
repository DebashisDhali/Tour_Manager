import 'package:flutter/material.dart';

class PurposeConfig {
  final String label;
  final String pluralLabel;
  final IconData icon;
  final Color color;

  PurposeConfig({
    required this.label,
    required this.pluralLabel,
    required this.icon,
    required this.color,
  });

  static PurposeConfig getConfig(String? purpose) {
    switch (purpose?.toLowerCase()) {
      case 'mess':
        return PurposeConfig(
          label: 'Mess',
          pluralLabel: 'Messes',
          icon: Icons.home_work_rounded,
          color: Colors.orange,
        );
      case 'event':
        return PurposeConfig(
          label: 'Event',
          pluralLabel: 'Events',
          icon: Icons.celebration_rounded,
          color: Colors.purple,
        );
      case 'office':
        return PurposeConfig(
          label: 'Project',
          pluralLabel: 'Projects',
          icon: Icons.business_center_rounded,
          color: Colors.blueGrey,
        );
      case 'party':
        return PurposeConfig(
          label: 'Party',
          pluralLabel: 'Parties',
          icon: Icons.outdoor_grill_rounded, // BBQ Icon
          color: Colors.deepOrange,
        );
      case 'tour':
      default:
        return PurposeConfig(
          label: 'Tour',
          pluralLabel: 'Tours',
          icon: Icons.beach_access_rounded,
          color: Colors.teal,
        );
    }
  }
}
