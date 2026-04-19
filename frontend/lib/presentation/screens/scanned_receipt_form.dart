import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/data/services/receipt_scanner_service.dart';
import 'package:intl/intl.dart';

class ScannedReceiptFormScreen extends ConsumerStatefulWidget {
  final String tourId;
  final ScannedReceiptData scannedData;

  const ScannedReceiptFormScreen({
    required this.tourId,
    required this.scannedData,
    Key? key,
  }) : super(key: key);

  @override
  ConsumerState<ScannedReceiptFormScreen> createState() =>
      _ScannedReceiptFormScreenState();
}

class _ScannedReceiptFormScreenState
    extends ConsumerState<ScannedReceiptFormScreen> {
  late TextEditingController _amountController;
  late TextEditingController _vendorController;
  late TextEditingController _dateController;
  late TextEditingController _titleController;
  String _selectedCategory = 'Others';
  late DateTime _selectedDate;

  final List<String> _categories = [
    'Food',
    'Hotel',
    'Transport',
    'Shopping',
    'Entertainment',
    'Medical',
    'Utilities',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.scannedData.amount?.toString() ?? '',
    );
    _vendorController = TextEditingController(
      text: widget.scannedData.vendor ?? '',
    );
    _titleController = TextEditingController(
      text: widget.scannedData.items.isNotEmpty
          ? widget.scannedData.items.first
          : '',
    );
    _selectedCategory = widget.scannedData.category;
    _selectedDate = widget.scannedData.date != null
        ? DateTime.tryParse(widget.scannedData.date!) ?? DateTime.now()
        : DateTime.now();
    _dateController = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(_selectedDate),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  void _submitExpense() {
    final amount = double.tryParse(_amountController.text);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter valid amount')),
      );
      return;
    }

    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter expense title')),
      );
      return;
    }

    final expenseData = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _titleController.text,
      'amount': amount,
      'category': _selectedCategory,
      'date': _selectedDate.toIso8601String(),
      'vendor': _vendorController.text,
      'rawOcrText': widget.scannedData.rawText,
      'items': widget.scannedData.items,
    };

    Navigator.pop(context, expenseData);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _vendorController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('✏️ Review Receipt'),
        elevation: 0,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Confidence indicator
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue[50],
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✨ Receipt scanned successfully',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please review and edit the extracted data',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Form
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Amount field
                  _buildFormField(
                    label: '💰 Amount',
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    hint: '0.00',
                  ),
                  const SizedBox(height: 16),

                  // Title/Description
                  _buildFormField(
                    label: '📝 Expense Title',
                    controller: _titleController,
                    hint: 'e.g., Restaurant meal',
                  ),
                  const SizedBox(height: 16),

                  // Vendor
                  _buildFormField(
                    label: '🏪 Vendor/Shop',
                    controller: _vendorController,
                    hint: 'e.g., McDonald\'s',
                  ),
                  const SizedBox(height: 16),

                  // Date
                  GestureDetector(
                    onTap: _selectDate,
                    child: _buildFormField(
                      label: '📅 Date',
                      controller: _dateController,
                      readOnly: true,
                      suffixIcon: Icons.calendar_today,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category dropdown
                  _buildCategoryDropdown(),
                  const SizedBox(height: 20),

                  // Scanned items preview
                  if (widget.scannedData.items.isNotEmpty) ...[
                    const Text(
                      '📋 Detected Items:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.scannedData.items
                            .take(5)
                            .map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• $item',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    if (widget.scannedData.items.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '... and ${widget.scannedData.items.length - 5} more items',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],

                  // Raw OCR text preview
                  const Text(
                    '🔍 Raw OCR Text:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[50],
                    ),
                    child: Text(
                      widget.scannedData.rawText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _submitExpense,
                      icon: const Icon(Icons.check),
                      label: const Text('✅ Add Expense'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    IconData? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            suffixIcon: suffixIcon != null ? Icon(suffixIcon) : null,
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🏷️ Category',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[50],
          ),
          child: DropdownButton<String>(
            value: _selectedCategory,
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCategory = value);
              }
            },
            isExpanded: true,
            underline: const SizedBox(),
            items: _categories.map((category) {
              return DropdownMenuItem(
                value: category,
                child: Text(category),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
