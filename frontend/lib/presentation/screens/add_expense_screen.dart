import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/app_database.dart' as models;
import 'package:frontend/data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';
import '../widgets/action_help_text.dart';
import '../widgets/premium_card.dart';
import 'package:frontend/presentation/screens/receipt_scanner_screen.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String tourId;
  final models.Expense? initialExpense;
  const AddExpenseScreen(
      {super.key, required this.tourId, this.initialExpense});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  String? _selectedPayerId;
  String _category = 'Food';
  String? _messCostType;

  bool _isMultiPayer = false;
  Map<String, double> _payerAmounts = {};

  bool _isCustomSplit = false;
  final Map<String, double> _splitAmounts = {};
  Set<String> _involvedMemberIds = {};

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialExpense != null) {
      _titleController.text = widget.initialExpense!.title;
      _amountController.text = widget.initialExpense!.amount.toStringAsFixed(0);
      _category = widget.initialExpense!.category;
      _selectedPayerId = widget.initialExpense!.payerId;
      _messCostType = widget.initialExpense!.messCostType;
      _loadExistingDetails();
    }
  }

  Future<void> _loadExistingDetails() async {
    final database = ref.read(databaseProvider);
    final payers = await (database.select(database.expensePayers)
          ..where((t) => t.expenseId.equals(widget.initialExpense!.id) & t.isDeleted.equals(false)))
        .get();
    if (payers.length > 1) {
      setState(() {
        _isMultiPayer = true;
        for (var p in payers) {
          _payerAmounts[p.userId] = p.amount;
        }
      });
    } else if (payers.length == 1) {
      setState(() {
        _isMultiPayer = false;
        _payerAmounts = {payers.first.userId: payers.first.amount};
        _selectedPayerId = payers.first.userId;
      });
    }

    final splits = await (database.select(database.expenseSplits)
          ..where((t) => t.expenseId.equals(widget.initialExpense!.id) & t.isDeleted.equals(false)))
        .get();
    final total = widget.initialExpense!.amount;
    final expectedEqual = total / (splits.isEmpty ? 1 : splits.length);
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

    setState(() {
      _involvedMemberIds = splits.map((s) => s.userId).toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));
    final membersAsync = ref.watch(tourMembersProvider(widget.tourId));
    final incomesAsync = ref.watch(tourIncomesProvider(widget.tourId));
    final settlementsAsync = ref.watch(tourSettlementsProvider(widget.tourId));
    final expensesAsync = ref.watch(tourExpensesProvider(widget.tourId));

    return tourAsync.when(
      data: (tour) {
        if (tour == null) {
          return const Scaffold(
              body: Center(child: Text("Tour no longer exists")));
        }
        // Local variable to ensure promotion works across the whole block
        final models.Tour activeTour = tour;

        final config = PurposeConfig.getConfig(activeTour.purpose);
        return membersAsync.when(
          data: (allMembers) {
            final members = allMembers.toList();
            if (members.isEmpty) {
              return Scaffold(
                appBar: AppBar(title: Text(config.addExpenseLabel)),
                body: const Center(child: Text("No members found.")),
              );
            }

            final categories = _getCategories(activeTour.purpose);
            if (!categories.contains(_category)) _category = categories.first;

            final activeMembers = members
                .where((m) => m.status.toLowerCase().trim() == 'active')
                .toList();

            // Balance Calculation
            final incomes = incomesAsync.value ?? [];
            final settlements = settlementsAsync.value ?? [];
            final otherExpenses = expensesAsync.value ?? [];
            final Map<String, double> userBalances = {};

            for (final m in members) {
              final uid = m.user.id.toLowerCase();
              final collected = incomes.where((i) => i.collectedBy.toLowerCase() == uid).fold(0.0, (sum, i) => sum + i.amount);
              final received = settlements.where((s) => s.toId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
              final given = settlements.where((s) => s.fromId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
              // Exclude current expense if editing
              final spent = otherExpenses
                  .where((e) => e.payerId?.toLowerCase() == uid && e.id.toLowerCase() != widget.initialExpense?.id.toLowerCase())
                  .fold(0.0, (sum, e) => sum + e.amount);
              
              userBalances[uid] = collected + received - given - spent;
            }
            if (_selectedPayerId == null ||
                !members.any((m) => m.user.id == _selectedPayerId)) {
              _selectedPayerId = activeMembers.isNotEmpty
                  ? activeMembers.first.user.id
                  : members.first.user.id;
            }

            if (_involvedMemberIds.isEmpty && widget.initialExpense == null) {
              _involvedMemberIds = activeMembers.map((m) => m.user.id).toSet();
              if (_involvedMemberIds.isEmpty) {
                _involvedMemberIds = {members.first.user.id};
              }
            }

            // Default to 'meal' (Bazar) for new Mess expenses so nothing slips through as custom split
            if (widget.initialExpense == null &&
                activeTour.purpose.toLowerCase() == 'mess' &&
                _messCostType == null) {
              _messCostType = 'meal';
            }

            if (!_isMultiPayer &&
                _payerAmounts.isEmpty &&
                widget.initialExpense == null) {
              final amount = double.tryParse(_amountController.text) ?? 0.0;
              _payerAmounts = {_selectedPayerId!: amount};
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(
                    widget.initialExpense == null
                        ? config.addExpenseLabel
                        : "Edit Details",
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.5)),
                backgroundColor: config.color,
                elevation: 0,
                flexibleSpace: Container(
                    decoration: BoxDecoration(gradient: config.gradient)),
                foregroundColor: Colors.white,
              ),
              body: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ActionHelpText(
                          'Fill the expense title and amount, choose payer(s), then select who shares the cost. Use custom split only when amounts differ.'),
                      PremiumCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInputLabel("Title", config.color),
                            TextFormField(
                              controller: _titleController,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              decoration: _getInputDecoration(
                                  hint: _getDescHint(activeTour.purpose),
                                  icon: Icons.title_rounded,
                                  color: config.color),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? "Required" : null,
                            ),
                            const SizedBox(height: 24),
                            _buildInputLabel("Amount", config.color),
                            TextFormField(
                              controller: _amountController,
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: config.color),
                              decoration: _getInputDecoration(
                                  hint: "0",
                                  icon: Icons.payments_rounded,
                                  color: config.color,
                                  prefix: "৳ "),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                setState(() {});
                                final amount = double.tryParse(v) ?? 0.0;
                                if (!_isMultiPayer &&
                                    _selectedPayerId != null) {
                                  _payerAmounts = {_selectedPayerId!: amount};
                                }
                              },
                              validator: (v) =>
                                  (double.tryParse(v ?? '') ?? 0) <= 0
                                      ? "Invalid amount"
                                      : null,
                            ),
                            if (activeTour.purpose.toLowerCase() == 'mess') ...[
                              const SizedBox(height: 24),
                              _buildInputLabel("Type", config.color),
                              SegmentedButton<String?>(
                                segments: const [
                                  ButtonSegment(
                                      value: 'meal',
                                      label: const Text('Bazar (Meal)',
                                          style: TextStyle(fontSize: 12)),
                                      icon: const Icon(Icons.shopping_basket_rounded,
                                          size: 16)),
                                  ButtonSegment(
                                      value: 'fixed',
                                      label: const Text('Rent (Fixed)',
                                          style: TextStyle(fontSize: 12)),
                                      icon: const Icon(Icons.home_work_rounded,
                                          size: 16)),
                                ],
                                selected: <String?>{_messCostType},
                                onSelectionChanged: (Set<String?> n) {
                                  if (n.isNotEmpty) {
                                    setState(() => _messCostType = n.first);
                                  }
                                },
                                style: SegmentedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surface,
                                  selectedBackgroundColor: config.color,
                                  selectedForegroundColor: Colors.white,
                                  side: BorderSide(
                                      color:
                                          config.color.withValues(alpha: 0.2)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildHeaderWithSwitch("Who Paid?", _isMultiPayer, (v) {
                        setState(() {
                          _isMultiPayer = v;
                          final amount =
                              double.tryParse(_amountController.text) ?? 0.0;
                          if (v) {
                            for (var m in members) {
                              _payerAmounts[m.user.id] = 0.0;
                            }
                            if (_selectedPayerId != null) {
                              _payerAmounts[_selectedPayerId!] = amount;
                            }
                          } else {
                            _payerAmounts = {_selectedPayerId!: amount};
                          }
                        });
                      }, config.color, "Split Payer"),
                      PremiumCard(
                        padding: const EdgeInsets.all(20),
                        child: _isMultiPayer
                            ? Column(
                                children: members
                                    .where((m) =>
                                        m.status.toLowerCase().trim() ==
                                            'active' ||
                                        (widget.initialExpense != null &&
                                            _payerAmounts
                                                .containsKey(m.user.id)))
                                    .map((m) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(m.user.name,
                                                          style: const TextStyle(
                                                              fontWeight: FontWeight
                                                                  .bold)),
                                                      Text(
                                                        "Balance: ৳${(userBalances[m.user.id.toLowerCase()] ?? 0.0).toStringAsFixed(0)}",
                                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                      ),
                                                    ],
                                                  )),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 120,
                                                child: TextFormField(
                                                  initialValue:
                                                      _payerAmounts[m.user.id]
                                                              ?.toStringAsFixed(
                                                                  0) ??
                                                          '0',
                                                  decoration:
                                                      _getInputDecoration(
                                                          hint: "0",
                                                          icon: Icons.add,
                                                          color: config.color,
                                                          prefix: "৳ ",
                                                          dense: true,
                                                          iconSize: 0),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  onChanged: (v) =>
                                                      _payerAmounts[m.user.id] =
                                                          double.tryParse(v) ??
                                                              0.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                              )
                            : DropdownButtonFormField<String>(
                                value: _selectedPayerId,
                                onChanged: (v) => setState(() {
                                  _selectedPayerId = v!;
                                  _payerAmounts = {
                                    v: double.tryParse(
                                            _amountController.text) ??
                                        0.0
                                  };
                                }),
                                items: members
                                    .where((m) =>
                                        m.status.toLowerCase().trim() ==
                                            'active' ||
                                        (widget.initialExpense != null &&
                                            _payerAmounts
                                                .containsKey(m.user.id)))
                                    .map((m) {
                                  final bal = userBalances[m.user.id.toLowerCase()] ?? 0.0;
                                  return DropdownMenuItem(
                                    value: m.user.id,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(m.user.name),
                                        Text(
                                          " ৳${bal.toStringAsFixed(0)}",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: bal > 0 ? Colors.green : Colors.orange,
                                            fontWeight: FontWeight.bold
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                decoration: _getInputDecoration(
                                    hint: "Select Payer",
                                    icon: Icons.person_rounded,
                                    color: config.color),
                              ),
                      ),
                      const SizedBox(height: 24),
                      _buildHeaderWithSwitch("Who Shared?", _isCustomSplit,
                          (v) {
                        setState(() {
                          _isCustomSplit = v;
                          if (v) {
                            final total =
                                double.tryParse(_amountController.text) ?? 0.0;
                            final equal = total /
                                (_involvedMemberIds.isEmpty
                                    ? 1
                                    : _involvedMemberIds.length);
                            for (var mId in _involvedMemberIds) {
                              _splitAmounts[mId] = equal;
                            }
                          }
                        });
                      }, config.color, "Custom Split"),
                      PremiumCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: members
                                  .where((m) =>
                                      m.status.toLowerCase().trim() ==
                                          'active' ||
                                      _involvedMemberIds.contains(m.user.id))
                                  .map((m) {
                                final isSelected =
                                    _involvedMemberIds.contains(m.user.id);
                                return FilterChip(
                                  label: Text(m.user.name,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface)),
                                  selected: isSelected,
                                  onSelected: (v) {
                                    setState(() {
                                      if (v) {
                                        _involvedMemberIds.add(m.user.id);
                                      } else if (_involvedMemberIds.length > 1)
                                        _involvedMemberIds.remove(m.user.id);

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
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: isSelected
                                              ? config.color
                                              : Theme.of(context)
                                                  .dividerColor)),
                                );
                              }).toList(),
                            ),
                            if (_isCustomSplit) ...[
                              const SizedBox(height: 24),
                              ...members
                                  .where((m) =>
                                      _involvedMemberIds.contains(m.user.id))
                                  .map((m) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                                child: Text(m.user.name,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold))),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 120,
                                              child: TextFormField(
                                                initialValue:
                                                    _splitAmounts[m.user.id]
                                                            ?.toStringAsFixed(
                                                                1) ??
                                                        '0',
                                                decoration: _getInputDecoration(
                                                    hint: "0",
                                                    icon: Icons.add,
                                                    color: config.color,
                                                    prefix: "৳ ",
                                                    dense: true,
                                                    iconSize: 0),
                                                keyboardType:
                                                    TextInputType.number,
                                                onChanged: (v) =>
                                                    _splitAmounts[m.user.id] =
                                                        double.tryParse(v) ??
                                                            0.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildInputLabel("Category", config.color),
                      PremiumCard(
                        padding: const EdgeInsets.all(8),
                        child: DropdownButtonFormField<String>(
                          value: categories.contains(_category)
                              ? _category
                              : categories.first,
                          items: categories
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _category = v;
                                if (_category.toLowerCase().trim() == 'rent' && 
                                    activeTour.purpose.toLowerCase() == 'mess') {
                                  _messCostType = 'fixed';
                                }
                              });
                            }
                          },
                          decoration: _getInputDecoration(
                              hint: "Category",
                              icon: config.icon,
                              color: config.color),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Receipt Scanner Button (Premium Feature)
                      if (widget.initialExpense == null)
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ReceiptScannerScreen(
                                      tourId: widget.tourId),
                                ),
                              );

                                if (result != null && mounted) {
                                  _titleController.text = result['title'] ?? '';
                                  _amountController.text =
                                      result['amount']?.toString() ?? '';
                                  _category = result['category'] ?? _category;
                                  
                                  if (_category.toLowerCase().trim() == 'rent' &&
                                      activeTour.purpose.toLowerCase() == 'mess') {
                                    _messCostType = 'fixed';
                                  }
                                  setState(() {});
                                }
                            },
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: const Text(
                              '📸 Or scan receipt',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(color: config.color, width: 2),
                              foregroundColor: config.color,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 64,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : () => _saveExpense(members, activeTour),
                          icon: _isSaving 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Icon(widget.initialExpense == null
                                  ? Icons.add_task_rounded
                                  : Icons.save_rounded),
                          label: Text(
                              _isSaving 
                                  ? "Saving..." 
                                  : (widget.initialExpense == null
                                      ? "Add Expense"
                                      : "Update Details"),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                              backgroundColor: config.color,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              shadowColor: config.color.withValues(alpha: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text("Error: $e")),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
    );
  }

  Widget _buildInputLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 1.2)),
    );
  }

  Widget _buildHeaderWithSwitch(String title, bool value,
      Function(bool) onChanged, Color color, String switchLabel) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: 1.2)),
          Row(
            children: [
              Text(switchLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3))),
              const SizedBox(width: 8),
              SizedBox(
                height: 24,
                width: 44,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: color,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _getInputDecoration(
      {required String hint,
      required IconData icon,
      required Color color,
      String? prefix,
      bool dense = false,
      double iconSize = 24}) {
    return InputDecoration(
      hintText: hint,
      prefixText: prefix,
      prefixIcon:
          iconSize > 0 ? Icon(icon, color: color, size: iconSize) : null,
      filled: true,
      fillColor: color.withValues(alpha: 0.05),
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.all(20),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: 2)),
    );
  }

  Future<void> _saveExpense(List<MemberWithStatus> members, models.Tour activeTour) async {
    if (_isSaving) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        final totalAmount = double.parse(_amountController.text);

        // Balance Check Logic
        if (!_isMultiPayer && _selectedPayerId != null) {
          final incomes = ref.read(tourIncomesProvider(widget.tourId)).value ?? [];
          final settlements = ref.read(tourSettlementsProvider(widget.tourId)).value ?? [];
          final otherExpenses = ref.read(tourExpensesProvider(widget.tourId)).value ?? [];
          
          final otherPayers = ref.read(databaseProvider).expensePayers.select().get();
          
          final uid = _selectedPayerId!.toLowerCase();
          final collected = incomes.where((i) => i.collectedBy.toLowerCase() == uid).fold(0.0, (sum, i) => sum + i.amount);
          final received = settlements.where((s) => s.toId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
          final given = settlements.where((s) => s.fromId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
          
          final expenseIds = otherExpenses.map((e) => e.id.toLowerCase()).toSet();
          double spent = otherExpenses
              .where((e) => e.payerId?.toLowerCase() == uid && e.id.toLowerCase() != widget.initialExpense?.id.toLowerCase())
              .fold(0.0, (sum, e) => sum + e.amount);
          
          // Also check multi-payer records
          final payers = await otherPayers;
          spent += payers
              .where((p) => p.userId.toLowerCase() == uid && expenseIds.contains(p.expenseId.toLowerCase()) && p.expenseId.toLowerCase() != widget.initialExpense?.id.toLowerCase())
              .fold(0.0, (sum, p) => sum + p.amount);
          
          final currentBalance = (collected + received) - (given + spent);

          if (totalAmount > currentBalance + 0.01) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Insufficient funds! Payer has only ৳${currentBalance.toStringAsFixed(0)} in hand."),
              backgroundColor: Colors.redAccent,
            ));
            return;
          }
        } else if (_isMultiPayer) {
          // Check for each payer in multi-payer mode
          final incomes = ref.read(tourIncomesProvider(widget.tourId)).value ?? [];
          final settlements = ref.read(tourSettlementsProvider(widget.tourId)).value ?? [];
          final otherPayers = ref.read(databaseProvider).expensePayers.select().get();
          final payers = await otherPayers;
          final expenseIds = otherExpenses.map((e) => e.id.toLowerCase()).toSet();

          for (final entry in _payerAmounts.entries) {
            final uid = entry.key.toLowerCase();
            final amount = entry.value;
            if (amount <= 0) continue;

            final collected = incomes.where((i) => i.collectedBy.toLowerCase() == uid).fold(0.0, (sum, i) => sum + i.amount);
            final received = settlements.where((s) => s.toId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
            final given = settlements.where((s) => s.fromId.toLowerCase() == uid).fold(0.0, (sum, s) => sum + s.amount);
            
            double spent = otherExpenses
                .where((e) => e.payerId?.toLowerCase() == uid && e.id.toLowerCase() != widget.initialExpense?.id.toLowerCase())
                .fold(0.0, (sum, e) => sum + e.amount);
            
            spent += payers
                .where((p) => p.userId.toLowerCase() == uid && expenseIds.contains(p.expenseId.toLowerCase()) && p.expenseId.toLowerCase() != widget.initialExpense?.id.toLowerCase())
                .fold(0.0, (sum, p) => sum + p.amount);
            
            final currentBalance = (collected + received) - (given + spent);

            if (amount > currentBalance + 0.01) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Insufficient funds for ${members.firstWhere((m) => m.user.id.toLowerCase() == uid).user.name}! (Has ৳${currentBalance.toStringAsFixed(0)})"),
                backgroundColor: Colors.redAccent,
              ));
              return;
            }
          }
        }

        final paidSum = _payerAmounts.values.fold(0.0, (sum, v) => sum + v);
        if ((paidSum - totalAmount).abs() > 0.01) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Payment sum ($paidSum৳) != $totalAmount৳")));
          return;
        }

        if (_isCustomSplit) {
          final splitSum = _splitAmounts.values.fold(0.0, (sum, v) => sum + v);
          if ((splitSum - totalAmount).abs() > 0.1) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Split sum ($splitSum৳) != $totalAmount৳")));
            return;
          }
        }

        final database = ref.read(databaseProvider);
        final expenseId = (widget.initialExpense?.id ?? const Uuid().v4()).toLowerCase();

        List<models.ExpenseSplit> splits = [];
        if (!_isCustomSplit) {
          final isMessBazar = activeTour.purpose.toLowerCase() == 'mess' && _messCostType != 'fixed';
          if (!isMessBazar) {
            final splitAmount = totalAmount /
                (_involvedMemberIds.isEmpty ? 1 : _involvedMemberIds.length);
            splits = members
                .where((m) => _involvedMemberIds.contains(m.user.id))
                .map((m) => models.ExpenseSplit(
                    id: const Uuid().v4().toLowerCase(),
                    expenseId: expenseId,
                    userId: m.user.id.toLowerCase(),
                    amount: splitAmount,
                    isSynced: false,
                    isDeleted: false))
                .toList();
          }
        } else {
          splits = _splitAmounts.entries
              .where((e) => _involvedMemberIds.contains(e.key))
              .map((e) => models.ExpenseSplit(
                  id: const Uuid().v4().toLowerCase(),
                  expenseId: expenseId,
                  userId: e.key.toLowerCase(),
                  amount: e.value,
                  isSynced: false,
                  isDeleted: false))
              .toList();
        }

        final payers = _payerAmounts.entries
            .where((e) => e.value > 0)
            .map((e) => models.ExpensePayer(
                id: const Uuid().v4().toLowerCase(),
                expenseId: expenseId,
                userId: e.key.toLowerCase(),
                amount: e.value,
                isSynced: false,
                isDeleted: false))
            .toList();

        final expense = models.Expense(
            id: expenseId,
            tourId: widget.tourId,
            payerId: _isMultiPayer ? null : _selectedPayerId,
            amount: totalAmount,
            title: _titleController.text,
            category: _category,
            messCostType: _messCostType,
            isSynced: false,
            isDeleted: false,
            createdAt: widget.initialExpense?.createdAt ?? DateTime.now());

        if (widget.initialExpense == null) {
          await database.addExpenseWithDetails(expense, splits, payers);
        } else {
          await database.updateExpenseWithDetails(expense, splits, payers);
        }

        if (mounted) {
          final currentUserId = ref.read(currentUserProvider).value?.id;
          if (currentUserId != null) {
            ref
                .read(syncServiceProvider)
                .startSync(currentUserId)
                .catchError((e) => debugPrint(e.toString()));
          }
          Navigator.pop(context);
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  String _getDescHint(String? purpose) {
    switch (purpose?.toLowerCase()) {
      case 'mess':
        return 'e.g. Lunch Bazar';
      case 'event':
        return 'e.g. Venue Booking';
      case 'project':
        return 'e.g. Server Cost';
      case 'party':
        return 'e.g. Snacks & Drinks';
      case 'tour':
        return 'e.g. Bus Fare';
      default:
        return 'e.g. Expense Title';
    }
  }

  List<String> _getCategories(String purpose) {
    switch (purpose.toLowerCase()) {
      case 'event':
        return ['Venue', 'Catering', 'Decor', 'Ads', 'Others'];
      case 'project':
        return ['API', 'Hosting', 'Hardware', 'Ads', 'Others'];
      case 'mess':
        return ['Bazar', 'Rent', 'Maid', 'Wifi', 'Others'];
      default:
        return ['Food', 'Transport', 'Hotel', 'Bills', 'Others'];
    }
  }
}
