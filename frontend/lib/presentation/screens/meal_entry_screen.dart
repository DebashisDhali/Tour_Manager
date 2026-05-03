import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart' as models;
import 'package:frontend/data/providers/app_providers.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../domain/logic/purpose_config.dart';
import '../widgets/action_help_text.dart';
import '../widgets/premium_card.dart';

class MealEntryScreen extends ConsumerStatefulWidget {
  final String tourId;
  final DateTime? initialDate;
  const MealEntryScreen({super.key, required this.tourId, this.initialDate});

  @override
  ConsumerState<MealEntryScreen> createState() => _MealEntryScreenState();
}

class _MealEntryScreenState extends ConsumerState<MealEntryScreen> {
  late DateTime _selectedDate;
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = false;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingRecords(List<MemberWithStatus> members) async {
    final db = ref.read(databaseProvider);
    final existing =
        await db.getMealRecordsForDate(widget.tourId, _selectedDate);

    for (var m in members) {
      final record = existing.where((r) => r.userId == m.user.id).firstOrNull;
      if (record != null) {
        _controllers[m.user.id]?.text = record.count.toStringAsFixed(1);
      } else {
        _controllers[m.user.id]?.text = "0.0";
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));

    return tourAsync.when(
      data: (tour) {
        final config = PurposeConfig.getConfig(tour?.purpose);

        return Scaffold(
          appBar: AppBar(
            title: const Text("Daily Meal Entry",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            flexibleSpace:
                Container(decoration: BoxDecoration(gradient: config.gradient)),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: membersAsync.when(
            data: (allMembers) {
              final members = allMembers
                  .where((m) => m.status.toLowerCase().trim() == 'active')
                  .toList();

              for (var m in members) {
                _controllers.putIfAbsent(
                    m.user.id, () => TextEditingController(text: "0.0"));
              }

              if (_isFirstLoad) {
                _isFirstLoad = false;
                Future.microtask(() => _loadExistingRecords(members));
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: config.color.withValues(alpha: 0.05),
                      border: Border(
                          bottom: BorderSide(
                              color: config.color.withValues(alpha: 0.1))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE').format(_selectedDate),
                              style: TextStyle(
                                  color: config.color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 1.2),
                            ),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(_selectedDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                          ],
                        ),
                        IconButton.filledTonal(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 30)),
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                    colorScheme: ColorScheme.fromSeed(
                                        seedColor: config.color)),
                                child: child!,
                              ),
                            );
                            if (date != null) {
                              setState(() => _selectedDate = date);
                              _loadExistingRecords(members);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_rounded,
                              size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                config.color.withValues(alpha: 0.1),
                            foregroundColor: config.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: ActionHelpText(
                        'Enter daily meal counts for each member using the + and - buttons, then save the daily entry.'),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final m = members[index];
                        return PremiumCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    config.color.withValues(alpha: 0.1),
                                child: Text(m.user.name[0].toUpperCase(),
                                    style: TextStyle(
                                        color: config.color,
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.user.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15)),
                                    const Text("Daily Meal Count",
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: config.color.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: config.color.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMealButton(
                                        m.user.id, -0.5, config.color),
                                    SizedBox(
                                      width: 76,
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: config.color
                                                .withValues(alpha: 0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: TextField(
                                          controller: _controllers[m.user.id],
                                          textAlign: TextAlign.center,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: config.color,
                                            letterSpacing: 0.5,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            hintText: "0.0",
                                            hintStyle: TextStyle(
                                              color: config.color
                                                  .withValues(alpha: 0.3),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d+\.?\d{0,1}$'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    _buildMealButton(
                                        m.user.id, 0.5, config.color),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 60,
                          child: FilledButton(
                            onPressed:
                                _isLoading ? null : () => _saveMeals(members),
                            style: FilledButton.styleFrom(
                              backgroundColor: config.color,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              elevation: 4,
                              shadowColor: config.shadowColor,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : const Text("Save Daily Entry ✨",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: config.color.withValues(alpha: 0.3)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              "Cancel",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: config.color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text("Error: $e")),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(body: Center(child: Text("Error: $e"))),
    );
  }

  Widget _buildMealButton(String userId, double delta, Color color) {
    return IconButton(
      icon:
          Icon(delta > 0 ? Icons.add_rounded : Icons.remove_rounded, size: 20),
      color: color,
      visualDensity: VisualDensity.compact,
      onPressed: () {
        final current = double.tryParse(_controllers[userId]!.text) ?? 0.0;
        final newVal = (current + delta).clamp(0.0, 10.0);
        _controllers[userId]!.text = newVal.toStringAsFixed(1);
        HapticFeedback.lightImpact();
      },
    );
  }

  Future<void> _saveMeals(List<MemberWithStatus> members) async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final existing =
          await db.getMealRecordsForDate(widget.tourId, _selectedDate);

      for (var m in members) {
        final count =
            double.tryParse(_controllers[m.user.id]?.text ?? "0.0") ?? 0.0;
        final existingRecord =
            existing.where((r) => r.userId == m.user.id).firstOrNull;

        final record = models.MealRecord(
          id: existingRecord?.id ?? const Uuid().v4(),
          tourId: widget.tourId,
          userId: m.user.id,
          date: DateTime(_selectedDate.year, _selectedDate.month,
              _selectedDate.day, 12, 0),
          count: count,
          isSynced: false,
          isDeleted: false,
        );

        await db.upsertMealRecord(record);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Entry saved! ✨"),
            behavior: SnackBarBehavior.floating));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
