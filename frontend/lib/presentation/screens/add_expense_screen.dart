import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../main.dart';
import '../../data/local/app_database.dart';
import '../../data/providers/app_providers.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String tourId;
  const AddExpenseScreen({super.key, required this.tourId});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  
  String? _selectedPayerId;
  String _category = 'Food';

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));

    return Scaffold(
      appBar: AppBar(title: const Text("Add New Expense")),
      body: membersAsync.when(
        data: (allMembers) {
          // Filter only active members (those who haven't left)
          final members = allMembers.where((m) => m.leftAt == null).toList();
          
          if (members.isEmpty) {
            return const Center(child: Text("No active members in this tour."));
          }
          
          _selectedPayerId ??= members.first.user.id;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionTitle("What was it for?"),
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                        labelText: "Description", 
                        hintText: "e.g. Dinner at Buffet",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.description_outlined)),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle("How much?"),
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                        labelText: "Amount", 
                        prefixText: "৳ ",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.payments_outlined)),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Details"),
                  DropdownButtonFormField<String>(
                    value: _category,
                    items: ['Food', 'Transport', 'Hotel', 'Shopping', 'Others'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _category = v!),
                    decoration: InputDecoration(
                        labelText: "Category", 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.category_outlined)),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    value: _selectedPayerId,
                    items: members.map((m) => DropdownMenuItem(value: m.user.id, child: Text(m.user.name))).toList(),
                    onChanged: (v) => setState(() => _selectedPayerId = v!),
                    decoration: InputDecoration(
                        labelText: "Paid By", 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 40),
                  Card(
                    color: Colors.tealAccent.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "This expense will be split among ${members.length} active members. " + 
                              (allMembers.length > members.length ? "${allMembers.length - members.length} departed members are excluded." : ""),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: () => _saveExpense(members), 
                    icon: const Icon(Icons.check),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text("Save Expense", style: TextStyle(fontSize: 16)),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
    );
  }

  Future<void> _saveExpense(List<MemberWithStatus> members) async {
    if (_formKey.currentState!.validate() && _selectedPayerId != null) {
        final db = ref.read(databaseProvider);
        final amount = double.parse(_amountController.text);
        final expenseId = const Uuid().v4();

        final splitAmount = amount / members.length;
        final splits = members.map((m) => ExpenseSplit(
            id: const Uuid().v4(),
            expenseId: expenseId,
            userId: m.user.id,
            amount: splitAmount,
            isSynced: false
        )).toList();

        final expense = Expense(
            id: expenseId,
            tourId: widget.tourId,
            payerId: _selectedPayerId!,
            amount: amount,
            title: _titleController.text,
            category: _category,
            isSynced: false,
            createdAt: DateTime.now()
        );

        await db.addExpenseWithSplits(expense, splits);
        if (mounted) Navigator.pop(context);
    }
  }
}
