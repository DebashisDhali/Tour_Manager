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
  final DateTime _date = DateTime.now();
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
    final users = await db.getTourActiveUsers(widget.tourId);
    if (mounted) {
      setState(() {
        _members = users;
        try {
          // Giver is ALWAYS Me (The current user)
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
              // Display Giver Name instead of Dropdown (since it's always 'Me')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: config.color.withValues(alpha: 0.1),
                  child: Icon(Icons.person, color: config.color),
                ),
                title: const Text("From (You)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                subtitle: Text(_members.firstWhere((u) => u.id == _selectedGiverId).name, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(),
              const SizedBox(height: 16),
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

  Future<void> _showInsufficientFundsDialog(double currentBalance) async {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text("Transfer Blocked", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "You cannot transfer funds you don't have in hand.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Current Balance", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text("৳${currentBalance.toStringAsFixed(0)}", 
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Please collect more funds or settle pending expenses before making this transfer.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("I Understand"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAllocation() async {
    if (_formKey.currentState!.validate()) {
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      
      // Calculate current user's balance to ensure they have funds to transfer
      final incomes = ref.read(tourIncomesProvider(widget.tourId)).value ?? [];
      final settlements = ref.read(tourSettlementsProvider(widget.tourId)).value ?? [];
      final expenses = ref.read(tourExpensesProvider(widget.tourId)).value ?? [];
      final payers = ref.read(tourPayersProvider(widget.tourId)).value ?? [];
      
      final uid = _selectedGiverId!.toLowerCase();
      
      final col = incomes.where((i) => i.collectedBy.toLowerCase() == uid).fold(0.0, (sum, i) => sum + i.amount);
      final rec = settlements.where((s) => s.toId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
      final giv = settlements.where((s) => s.fromId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
      
      final singlePayerSpt = expenses
          .where((e) => e.payerId?.toLowerCase() == uid)
          .fold(0.0, (sum, e) => sum + e.amount);
      final multiPayerSpt =
          payers.where((p) => p.userId.toLowerCase() == uid).fold(0.0, (sum, p) => sum + p.amount);
          
      final currentBalance = (col + rec) - (giv + singlePayerSpt + multiPayerSpt);

      if (amount > currentBalance + 0.01) {
        if (mounted) {
          await _showInsufficientFundsDialog(currentBalance);
        }
        return;
      }

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
