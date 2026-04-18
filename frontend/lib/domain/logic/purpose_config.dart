import 'package:flutter/material.dart';

class PurposeConfig {
  final String id;
  final String name;
  final String label;
  final String pluralLabel;
  final String memberLabel;
  final String addExpenseLabel;
  final String expenseListLabel;
  final String setupLabel;
  final IconData icon;
  final Color color;
  final LinearGradient gradient;
  final Color shadowColor;

  PurposeConfig({
    required this.id,
    required this.name,
    required this.label,
    required this.pluralLabel,
    this.memberLabel = 'Members',
    this.addExpenseLabel = 'Add Expense',
    this.expenseListLabel = 'Expenses',
    this.setupLabel = 'Setup',
    required this.icon,
    required this.color,
    required this.gradient,
    required this.shadowColor,
  });

  static List<PurposeConfig> get allConfigs => [
        getConfig('project'),
        getConfig('party'),
        getConfig('tour'),
        getConfig('mess'),
        getConfig('event'),
      ];

  static PurposeConfig getConfig(String? purpose) {
    switch (purpose?.toLowerCase()) {
      case 'mess':
        return PurposeConfig(
          id: 'mess',
          name: 'Mess',
          label: 'Mess',
          pluralLabel: 'Messes',
          memberLabel: 'Mess Mates',
          addExpenseLabel: 'Add Mess Cost',
          expenseListLabel: 'Mess Costs',
          setupLabel: 'Mess Setup',
          icon: Icons.home_work_rounded,
          color: const Color(0xFFF59E0B), // Amber 500
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
        );
      case 'event':
        return PurposeConfig(
          id: 'event',
          name: 'Event',
          label: 'Event',
          pluralLabel: 'Events',
          memberLabel: 'Members',
          addExpenseLabel: 'Add Tour Expense',
          expenseListLabel: 'Tour Expenses',
          setupLabel: 'Tour Setup',
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF8B5CF6), // Violet 500
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
        );
      case 'project':
      case 'office':
        return PurposeConfig(
          id: 'project',
          name: 'Project',
          label: 'Project',
          pluralLabel: 'Projects',
          memberLabel: 'Members',
          addExpenseLabel: 'Add Tour Expense',
          expenseListLabel: 'Tour Expenses',
          setupLabel: 'Tour Setup',
          icon: Icons.layers_rounded,
          color: const Color(0xFF3B82F6), // Blue 500
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: const Color(0xFF3B82F6).withValues(alpha: 0.2),
        );
      case 'party':
        return PurposeConfig(
          id: 'party',
          name: 'Party',
          label: 'Party',
          pluralLabel: 'Parties',
          memberLabel: 'Members',
          addExpenseLabel: 'Add Tour Expense',
          expenseListLabel: 'Tour Expenses',
          setupLabel: 'Tour Setup',
          icon: Icons.nightlife_rounded,
          color: const Color(0xFFEF4444), // Red 500
          gradient: const LinearGradient(
            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
        );
      case 'tour':
        return PurposeConfig(
          id: 'tour',
          name: 'Tour',
          label: 'Tour',
          pluralLabel: 'Tours',
          memberLabel: 'Members',
          addExpenseLabel: 'Add Tour Expense',
          expenseListLabel: 'Tour Expenses',
          setupLabel: 'Tour Setup',
          icon: Icons.explore_rounded,
          color: const Color(0xFF10B981), // Emerald 500
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.2),
        );
      default:
        return PurposeConfig(
          id: 'project',
          name: 'Project',
          label: 'Project',
          pluralLabel: 'Projects',
          memberLabel: 'Members',
          addExpenseLabel: 'Add Tour Expense',
          expenseListLabel: 'Tour Expenses',
          setupLabel: 'Tour Setup',
          icon: Icons.layers_rounded,
          color: const Color(0xFF3B82F6), // Blue 500
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shadowColor: const Color(0xFF3B82F6).withValues(alpha: 0.2),
        );
    }
  }
}
