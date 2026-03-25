import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';
import '../../main.dart';
import 'package:uuid/uuid.dart';

class AddIncomeDialog extends ConsumerStatefulWidget {
  final String tourId;

  const AddIncomeDialog({super.key, required this.tourId});

  @override
  ConsumerState<AddIncomeDialog> createState() => _AddIncomeDialogState();
}

class _AddIncomeDialogState extends ConsumerState<AddIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  final _descController = TextEditingController();
  String? _selectedCollectorId;
  DateTime _date = DateTime.now();
  List<User> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final db = ref.read(databaseProvider);
    final users = await db.getTourUsers(widget.tourId);
    if (mounted) {
      setState(() {
        _members = users;
        // Find 'Me' and set as default collector
        try {
          final me = users.firstWhere((u) => u.isMe);
          _selectedCollectorId = me.id;
        } catch (_) {
          if (users.isNotEmpty) _selectedCollectorId = users.first.id;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));
    final config = PurposeConfig.getConfig(tourAsync.value?.purpose);

    return AlertDialog(
      title: Text("Add ${config.label} Fund"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _sourceController,
                decoration: const InputDecoration(labelText: "Source", hintText: "e.g. Dept, Ticket Sales, Senior"),
                validator: (value) => value == null || value.isEmpty ? 'Please enter a source' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: "Amount", prefixText: "৳"),
                keyboardType: TextInputType.number,
                validator: (value) => value == null || value.isEmpty ? 'Please enter an amount' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCollectorId,
                decoration: const InputDecoration(labelText: "Collected By (Who holds the money?)"),
                items: _members.map((user) {
                  return DropdownMenuItem(
                    value: user.id,
                    child: Text(user.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedCollectorId = val),
                 validator: (value) => value == null ? 'Please select a collector' : null,
              ),
              const SizedBox(height: 16),
               TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: "Description (Optional)"),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _saveIncome,
          style: FilledButton.styleFrom(backgroundColor: config.color),
          child: const Text("Save"),
        ),
      ],
    );
  }

  Future<void> _saveIncome() async {
    if (_formKey.currentState!.validate()) {
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      
      final income = ProgramIncome(
        id: const Uuid().v4(),
        tourId: widget.tourId,
        amount: amount,
        source: _sourceController.text,
        description: _descController.text,
        collectedBy: _selectedCollectorId!,
        date: _date,
        isSynced: false,
      );

      final db = ref.read(databaseProvider);
      await db.createProgramIncome(income);
      
      if (mounted) Navigator.pop(context);
    }
  }
}
