import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../main.dart';
import '../../data/local/app_database.dart' as models;
import '../../data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String tourId;
  final models.Expense? initialExpense;
  const AddExpenseScreen({super.key, required this.tourId, this.initialExpense});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  
  String? _selectedPayerId;
  String _category = 'Food';
  
  // Multi-payer support
  bool _isMultiPayer = false;
  Map<String, double> _payerAmounts = {}; // userId -> amount

  // Custom split support
  bool _isCustomSplit = false;
  Map<String, double> _splitAmounts = {}; // userId -> amount
  Set<String> _involvedMemberIds = {}; // Who shares this expense?

  @override
  void initState() {
    super.initState();
    if (widget.initialExpense != null) {
      _titleController.text = widget.initialExpense!.title;
      _amountController.text = widget.initialExpense!.amount.toStringAsFixed(0);
      _category = widget.initialExpense!.category;
      _selectedPayerId = widget.initialExpense!.payerId;
      _loadExistingDetails();
    }
  }

  Future<void> _loadExistingDetails() async {
    final database = ref.read(databaseProvider);
    
    // Load Payers
    final payers = await (database.select(database.expensePayers)..where((t) => t.expenseId.equals(widget.initialExpense!.id))).get();
    if (payers.length > 1) {
      setState(() {
        _isMultiPayer = true;
        for (var p in payers) {
          _payerAmounts[p.userId] = p.amount;
        }
      });
    }

    // Load Splits
    final splits = await (database.select(database.expenseSplits)..where((t) => t.expenseId.equals(widget.initialExpense!.id))).get();
    // Check if it's NOT an equal split
    final total = widget.initialExpense!.amount;
    final expectedEqual = total / splits.length;
    bool isCustom = false;
    for (var s in splits) {
      if ((s.amount - expectedEqual).abs() > 0.1) {
        isCustom = true;
        break;
      }
    }

    if (isCustom) {
      setState(() {
        _isCustomSplit = true;
        for (var s in splits) {
          _splitAmounts[s.userId] = s.amount;
        }
      });
    }

    // Always load involved members from splits
    setState(() {
      _involvedMemberIds = splits.map((s) => s.userId).toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    final currentUserAsync = ref.watch(currentUserProvider);
    final config = PurposeConfig.getConfig(currentUserAsync.value?.purpose);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialExpense == null ? "Add New Expense" : "Edit Expense"),
        backgroundColor: config.color,
        foregroundColor: Colors.white,
      ),
      body: membersAsync.when(
        data: (allMembers) {
          final members = allMembers.where((m) => m.leftAt == null).toList();
          if (members.isEmpty) return Center(child: Text("No active members in this ${config.label.toLowerCase()}."));
          
          _selectedPayerId ??= members.first.user.id;
          
          // Initial selection: All members
          if (_involvedMemberIds.isEmpty && widget.initialExpense == null) {
            _involvedMemberIds = members.map((m) => m.user.id).toSet();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionTitle("What was it for?", config.color),
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                        labelText: "Description", 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: Icon(Icons.description_outlined, color: config.color)),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle("How much?", config.color),
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                        labelText: "Total Amount", 
                        prefixText: "৳ ",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: Icon(Icons.payments_outlined, color: config.color)),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    onChanged: (v) {
                       setState(() {}); // Rebuild to clear error
                       final amount = double.tryParse(v) ?? 0.0;
                       if (!_isMultiPayer && _selectedPayerId != null) {
                         _payerAmounts = { _selectedPayerId!: amount };
                       }
                       if (!_isCustomSplit) {
                          // Will be handled in save, but good to keep state clean
                       }
                    },
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? "Invalid amount" : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle("Who Paid?", config.color),
                      Row(
                        children: [
                          const Text("Combined Payment?", style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _isMultiPayer, 
                            onChanged: (v) => setState(() {
                              _isMultiPayer = v;
                              if (v) {
                                // Initialize all to 0 except the previously selected one
                                for (var m in members) {
                                  _payerAmounts[m.user.id] = 0.0;
                                }
                                if (_selectedPayerId != null) {
                                  _payerAmounts[_selectedPayerId!] = double.tryParse(_amountController.text) ?? 0.0;
                                }
                              } else {
                                // Revert to single payer
                                _payerAmounts = { _selectedPayerId!: double.tryParse(_amountController.text) ?? 0.0 };
                              }
                            }),
                            activeColor: config.color,
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  if (!_isMultiPayer)
                    DropdownButtonFormField<String>(
                      value: _selectedPayerId,
                      items: members.map((m) => DropdownMenuItem(value: m.user.id, child: Text(m.user.name))).toList(),
                      onChanged: (v) => setState(() {
                        _selectedPayerId = v!;
                        if (!_isMultiPayer) {
                          _payerAmounts = { v: double.tryParse(_amountController.text) ?? 0.0 };
                        }
                      }),
                      decoration: InputDecoration(
                          labelText: "Paid By", 
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.person_outline)),
                    )
                  else
                    ...members.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text(m.user.name)),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: _payerAmounts[m.user.id]?.toStringAsFixed(0) ?? '0',
                              decoration: const InputDecoration(prefixText: "৳ ", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _payerAmounts[m.user.id] = double.tryParse(v) ?? 0.0,
                            ),
                          ),
                        ],
                      ),
                    )).toList(),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle("Split Between", config.color),
                      Row(
                        children: [
                          const Text("Custom Split?", style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _isCustomSplit, 
                            onChanged: (v) => setState(() {
                              _isCustomSplit = v;
                              if (v) {
                                final total = double.tryParse(_amountController.text) ?? 0.0;
                                final equal = total / members.length;
                                for (var m in members) {
                                  _splitAmounts[m.user.id] = equal;
                                }
                              }
                            }),
                            activeColor: config.color,
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Member Selection for Split
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: members.map((m) {
                        final isSelected = _involvedMemberIds.contains(m.user.id);
                        return FilterChip(
                          label: Text(m.user.name, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                          selected: isSelected,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _involvedMemberIds.add(m.user.id);
                              } else {
                                if (_involvedMemberIds.length > 1) {
                                  _involvedMemberIds.remove(m.user.id);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("At least one person must share the cost")));
                                }
                              }
                              
                              // If custom split is on, update split amounts accordingly
                              if (_isCustomSplit) {
                                if (v) {
                                  _splitAmounts[m.user.id] = 0.0;
                                } else {
                                  _splitAmounts.remove(m.user.id);
                                }
                              }
                            });
                          },
                          selectedColor: config.color,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                  ),

                  if (!_isCustomSplit)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        "Split equally between ${_involvedMemberIds.length} members",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    )
                  else
                    ...members.where((m) => _involvedMemberIds.contains(m.user.id)).map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text(m.user.name)),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              key: ValueKey("split_${m.user.id}"),
                              initialValue: _splitAmounts[m.user.id]?.toStringAsFixed(1) ?? '0',
                              decoration: const InputDecoration(prefixText: "৳ ", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _splitAmounts[m.user.id] = double.tryParse(v) ?? 0.0,
                            ),
                          ),
                        ],
                      ),
                    )).toList(),

                  const SizedBox(height: 24),
                  _buildSectionTitle("${config.label} Details", config.color),
                  DropdownButtonFormField<String>(
                    value: _category,
                    items: ['Food', 'Transport', 'Hotel', 'Shopping', 'Others'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _category = v!),
                    decoration: InputDecoration(
                        labelText: "Category", 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.category_outlined)),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: () => _saveExpense(members), 
                    icon: Icon(widget.initialExpense == null ? Icons.check : Icons.save),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(widget.initialExpense == null ? "Save Expense" : "Update Expense", style: const TextStyle(fontSize: 16)),
                    ),
                    style: FilledButton.styleFrom(backgroundColor: config.color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Future<void> _saveExpense(List<MemberWithStatus> members) async {
    if (_formKey.currentState!.validate()) {
        final totalAmount = double.parse(_amountController.text);
        
        // Validate Multi-payer Sum
        final paidSum = _payerAmounts.values.fold(0.0, (sum, v) => sum + v);
        if ((paidSum - totalAmount).abs() > 0.01) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sum of payments ($paidSum ৳) must equal total ($totalAmount ৳)")));
          return;
        }

        // Validate Custom Split Sum
        if (_isCustomSplit) {
          final splitSum = _splitAmounts.values.fold(0.0, (sum, v) => sum + v);
          if ((splitSum - totalAmount).abs() > 0.1) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sum of splits ($splitSum ৳) must equal total ($totalAmount ৳)")));
            return;
          }
        }

        final database = ref.read(databaseProvider);
        final expenseId = widget.initialExpense?.id ?? const Uuid().v4();

        // 1. Create Splits (Who owes)
        List<models.ExpenseSplit> splits;
        if (!_isCustomSplit) {
          final splitAmount = totalAmount / (_involvedMemberIds.isEmpty ? 1 : _involvedMemberIds.length);
          splits = members
            .where((m) => _involvedMemberIds.contains(m.user.id))
            .map((m) => models.ExpenseSplit(id: const Uuid().v4(), expenseId: expenseId, userId: m.user.id, amount: splitAmount, isSynced: false)).toList();
        } else {
          splits = _splitAmounts.entries
            .where((e) => _involvedMemberIds.contains(e.key))
            .map((e) => models.ExpenseSplit(id: const Uuid().v4(), expenseId: expenseId, userId: e.key, amount: e.value, isSynced: false)).toList();
        }

        // 2. Create Payers (Who paid)
        final payers = _payerAmounts.entries
          .where((e) => e.value > 0)
          .map((e) => models.ExpensePayer(id: const Uuid().v4(), expenseId: expenseId, userId: e.key, amount: e.value, isSynced: false)).toList();

        // Determine Primary Payer (for DB constraints and summary text)
        String? primaryPayerId;
        if (!_isMultiPayer) {
           primaryPayerId = _selectedPayerId;
        } else {
           // Find the person who paid the most to be the 'face' of the expense
           // This avoids NULL constraint crashes and gives a reasonable summary
           final maxPayer = _payerAmounts.entries
             .where((e) => e.value > 0)
             .reduce((curr, next) => curr.value > next.value ? curr : next);
           primaryPayerId = maxPayer.key;
        }

        final expense = models.Expense(
            id: expenseId,
            tourId: widget.tourId,
            payerId: primaryPayerId,
            amount: totalAmount,
            title: _titleController.text,
            category: _category,
            isSynced: false,
            createdAt: widget.initialExpense?.createdAt ?? DateTime.now()
        );

        if (widget.initialExpense == null) {
          await database.addExpenseWithDetails(expense, splits, payers);
        } else {
          await database.updateExpenseWithDetails(expense, splits, payers);
        }
        
        if (mounted) {
           ref.read(syncServiceProvider).startSync(members.first.user.id).catchError((e) => print("Auto-sync failed: $e"));
           Navigator.pop(context);
        }
    }
  }
}
