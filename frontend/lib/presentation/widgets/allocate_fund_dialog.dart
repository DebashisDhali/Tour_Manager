import 'package:flutter/material.dart';
import '../../domain/logic/purpose_config.dart';
import '../../data/providers/app_providers.dart';
import '../../data/local/app_database.dart';
import '../widgets/action_help_text.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AllocateFundDialog extends ConsumerStatefulWidget {
  final String tourId;
  const AllocateFundDialog({super.key, required this.tourId});

  @override
  ConsumerState<AllocateFundDialog> createState() => _AllocateFundDialogState();
}

class _AllocateFundDialogState extends ConsumerState<AllocateFundDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String? _selectedGiverId;
  String? _selectedReceiverId;
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
        try {
          // Default Giver is Me
          _selectedGiverId = users.firstWhere((u) => u.isMe).id;
        } catch (_) {
          if (users.isNotEmpty) _selectedGiverId = users.first.id;
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
      title: Text("${config.label} Fund Transfer"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ActionHelpText(
                  'Choose who is giving money, who is receiving, enter the amount, and then tap Transfer.'),
              DropdownButtonFormField<String>(
                value: _selectedGiverId,
                decoration: const InputDecoration(labelText: "From (Giver)"),
                items: _members.map((user) {
                  return DropdownMenuItem(
                    value: user.id,
                    child: Text(user.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedGiverId = val),
                validator: (value) => value == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedReceiverId,
                decoration: const InputDecoration(labelText: "To (Receiver)"),
                items:
                    _members.where((u) => u.id != _selectedGiverId).map((user) {
                  return DropdownMenuItem(
                    value: user.id,
                    child: Text(user.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedReceiverId = val),
                validator: (value) => value == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration:
                    const InputDecoration(labelText: "Amount", prefixText: "৳"),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
        FilledButton(
          onPressed: _saveAllocation,
          style: FilledButton.styleFrom(backgroundColor: config.color),
          child: const Text("Transfer"),
        ),
      ],
    );
  }

  Future<void> _saveAllocation() async {
    if (_formKey.currentState!.validate()) {
      final amount = double.tryParse(_amountController.text) ?? 0.0;

      final settlement = Settlement(
        id: const Uuid().v4(),
        tourId: widget.tourId,
        fromId: _selectedGiverId!,
        toId: _selectedReceiverId!,
        amount: amount,
        date: _date,
        isSynced: false,
        isDeleted: false,
      );

      final db = ref.read(databaseProvider);
      await db.createSettlement(settlement);
      if (mounted) Navigator.pop(context);
    }
  }
}
