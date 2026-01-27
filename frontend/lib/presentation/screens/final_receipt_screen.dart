import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import '../../data/local/app_database.dart' as models;
import '../../data/utils/export_delegate.dart';
import '../../domain/logic/settlement_calculator.dart';
import '../../domain/logic/purpose_config.dart';
import '../../data/providers/app_providers.dart';
import '../../main.dart';

class FinalReceiptScreen extends ConsumerWidget {
  final String tourId;

  const FinalReceiptScreen({
    super.key,
    required this.tourId,
  });

  Future<void> _printReceipt(
    models.Tour tour,
    List<models.User> users,
    List<models.Expense> expenses,
    List<models.ExpenseSplit> splits,
    List<models.ExpensePayer> tourPayers,
    List<models.Settlement> previousSettlements,
    List<SettlementInstruction> settlementInstructions,
    String? purpose,
  ) async {
    final config = PurposeConfig.getConfig(purpose);
    final pdf = pw.Document();

    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('${config.label.toUpperCase()} COST RECEIPT', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(tour.name, style: pw.TextStyle(fontSize: 18)),
                ),
                pw.Center(
                  child: pw.Text(
                    tour.startDate == null 
                        ? 'Active Adventure' 
                        : '${DateFormat('MMM dd, yyyy').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Divider(),
                pw.SizedBox(height: 12),
                
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total ${config.label} Cost:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('${totalCost.toStringAsFixed(0)} BDT'),
                  ],
                ),
                pw.SizedBox(height: 24),

                pw.Text('MEMBER CONTRIBUTIONS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Name', 'Paid', 'Adj', 'Share', 'Balance'],
                  cellAlignment: pw.Alignment.centerRight,
                  headerAlignment: pw.Alignment.centerRight,
                  data: users.map<List<String>>((u) {
                    final expensesWithPayerRecords = tourPayers.map((p) => p.expenseId).toSet();
                    double paidOnExpenses = tourPayers.where((p) => p.userId == u.id).fold(0.0, (sum, p) => sum + p.amount);
                    for (var e in expenses) {
                      if (!expensesWithPayerRecords.contains(e.id) && e.payerId == u.id) {
                        paidOnExpenses += e.amount;
                      }
                    }
                    final share = splits.where((s) => s.userId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final paidSettlements = previousSettlements.where((s) => s.fromId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final receivedSettlements = previousSettlements.where((s) => s.toId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final adjustment = paidSettlements - receivedSettlements;
                    
                    final balance = (paidOnExpenses + adjustment) - share;
                    return [
                      u.name,
                      paidOnExpenses.toStringAsFixed(0),
                      '${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(0)}',
                      share.toStringAsFixed(0),
                      '${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)}',
                    ];
                  }).toList(),
                ),
                
                pw.SizedBox(height: 24),
                pw.Text('SETTLEMENT PLAN', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (settlementInstructions.isEmpty)
                   pw.Text('• All debts settled!')
                else
                  ...settlementInstructions.map((s) => pw.Text('• ${s.payerName} pays ${s.amount.toStringAsFixed(0)} to ${s.receiverName}')),
                
                pw.Spacer(),
                pw.Divider(),
                pw.Center(
                  child: pw.Text('Generated by Manager App', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _shareReceipt(
    models.Tour tour,
    List<models.User> users,
    List<models.Expense> expenses,
    List<models.ExpenseSplit> splits,
    List<models.ExpensePayer> tourPayers,
    List<models.Settlement> previousSettlements,
    List<SettlementInstruction> settlementInstructions,
    String? purpose,
  ) async {
    final config = PurposeConfig.getConfig(purpose);
    final pdfBytes = await _generatePdfBytes(tour, users, expenses, splits, tourPayers, previousSettlements, settlementInstructions, purpose);
    
    final fileName = "${tour.name.replaceAll(' ', '_')}_Receipt.pdf";
    
    await ExportDelegate.shareFile(
      pdfBytes, 
      fileName, 
      subject: '${config.label} Cost Receipt: ${tour.name}'
    );
  }

  Future<Uint8List> _generatePdfBytes(
    models.Tour tour,
    List<models.User> users,
    List<models.Expense> expenses,
    List<models.ExpenseSplit> splits,
    List<models.ExpensePayer> tourPayers,
    List<models.Settlement> previousSettlements,
    List<SettlementInstruction> settlementInstructions,
    String? purpose,
  ) async {
    final config = PurposeConfig.getConfig(purpose);
    final pdf = pw.Document();
    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text('${config.label.toUpperCase()} COST RECEIPT', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
                pw.SizedBox(height: 8),
                pw.Center(child: pw.Text(tour.name, style: pw.TextStyle(fontSize: 18))),
                pw.Center(child: pw.Text(tour.startDate == null ? 'Active' : '${DateFormat('MMM dd, yyyy').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}', style: const pw.TextStyle(fontSize: 12))),
                pw.SizedBox(height: 24),
                pw.Divider(),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total ${config.label} Cost:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('${totalCost.toStringAsFixed(0)} BDT'),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text('MEMBER CONTRIBUTIONS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Name', 'Paid', 'Adj', 'Share', 'Balance'],
                  cellAlignment: pw.Alignment.centerRight,
                  headerAlignment: pw.Alignment.centerRight,
                  data: users.map<List<String>>((u) {
                    final expensesWithPayerRecords = tourPayers.map((p) => p.expenseId).toSet();
                    double paidOnExpenses = tourPayers.where((p) => p.userId == u.id).fold(0.0, (sum, p) => sum + p.amount);
                    for (var e in expenses) {
                      if (!expensesWithPayerRecords.contains(e.id) && e.payerId == u.id) {
                        paidOnExpenses += e.amount;
                      }
                    }
                    
                    final share = splits.where((s) => s.userId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final paidSettlements = previousSettlements.where((s) => s.fromId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final receivedSettlements = previousSettlements.where((s) => s.toId == u.id).fold(0.0, (sum, s) => sum + s.amount);
                    final adjustment = paidSettlements - receivedSettlements;
                    
                    final balance = (paidOnExpenses + adjustment) - share;
                    
                    return [
                      u.name, 
                      paidOnExpenses.toStringAsFixed(0), 
                      '${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(0)}',
                      share.toStringAsFixed(0), 
                      '${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)}'
                    ];
                  }).toList(),
                ),
                pw.SizedBox(height: 24),
                pw.Text('SETTLEMENT PLAN', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (settlementInstructions.isEmpty)
                   pw.Text('• All debts settled!')
                else
                  ...settlementInstructions.map((s) => pw.Text('• ${s.payerName} pays ${s.amount.toStringAsFixed(0)} to ${s.receiverName}')),
                pw.Spacer(),
                pw.Divider(),
                pw.Center(child: pw.Text('Generated by Manager App', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey))),
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourAsync = ref.watch(singleTourProvider(tourId));
    final usersAsync = ref.watch(tourUsersProvider(tourId));
    final expensesAsync = ref.watch(tourExpensesProvider(tourId));
    final splitsAsync = ref.watch(tourSplitsProvider(tourId));
    final settlementsAsync = ref.watch(tourSettlementsProvider(tourId));
    final payersAsync = ref.watch(tourPayersProvider(tourId));
    final currentUserAsync = ref.watch(currentUserProvider);

    if (tourAsync.isLoading || usersAsync.isLoading || expensesAsync.isLoading || 
        splitsAsync.isLoading || settlementsAsync.isLoading || payersAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tour = tourAsync.value;
    final users = usersAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];
    final splits = splitsAsync.value ?? [];
    final previousSettlements = settlementsAsync.value ?? [];
    final tourPayers = payersAsync.value ?? [];
    final purpose = currentUserAsync.value?.purpose;

    if (tour == null) return const Scaffold(body: Center(child: Text("Tour not found")));

    final calculator = SettlementCalculator();
    final settlementInstructions = calculator.calculate(expenses, splits, tourPayers, users, previousSettlements);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Final Statement"),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareReceipt(tour, users, expenses, splits, tourPayers, previousSettlements, settlementInstructions, purpose),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () => _printReceipt(tour, users, expenses, splits, tourPayers, previousSettlements, settlementInstructions, purpose),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildReceiptPaper(context, tour, users, expenses, splits, tourPayers, previousSettlements, settlementInstructions, purpose),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _shareReceipt(tour, users, expenses, splits, tourPayers, previousSettlements, settlementInstructions, purpose),
                      icon: const Icon(Icons.share),
                      label: const Text("Share"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _printReceipt(tour, users, expenses, splits, tourPayers, previousSettlements, settlementInstructions, purpose),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text("Print"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptPaper(
    BuildContext context,
    models.Tour tour,
    List<models.User> users,
    List<models.Expense> expenses,
    List<models.ExpenseSplit> splits,
    List<models.ExpensePayer> tourPayers,
    List<models.Settlement> previousSettlements,
    List<SettlementInstruction> settlementInstructions,
    String? purpose,
  ) {
    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final config = PurposeConfig.getConfig(purpose);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          const Text("FINAL RECEIPT", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 4),
          const Divider(),
          const SizedBox(height: 12),
          Text(tour.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(
            tour.startDate == null 
                ? 'Active Adventure' 
                : '${DateFormat('MMM dd, yyyy').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildRow("Total ${config.label} Cost", "${totalCost.toStringAsFixed(0)} ৳", config.color, isBold: true),
          _buildRow("Total Members", "${users.length}", config.color),
          const SizedBox(height: 24),
          const Align(alignment: Alignment.centerLeft, child: Text("CONTRIBUTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(height: 8),
          ...users.map((u) {
            final expensesWithPayerRecords = tourPayers.map((p) => p.expenseId).toSet();
            double paidOnExpenses = tourPayers.where((p) => p.userId == u.id).fold(0.0, (sum, p) => sum + p.amount);
            for (var e in expenses) {
              if (!expensesWithPayerRecords.contains(e.id) && e.payerId == u.id) {
                paidOnExpenses += e.amount;
              }
            }
            
            final share = splits.where((s) => s.userId == u.id).fold(0.0, (sum, s) => sum + s.amount);
            final paidSettlements = previousSettlements.where((s) => s.fromId == u.id).fold(0.0, (sum, s) => sum + s.amount);
            final receivedSettlements = previousSettlements.where((s) => s.toId == u.id).fold(0.0, (sum, s) => sum + s.amount);
            final adjustment = paidSettlements - receivedSettlements;
            
            final balance = (paidOnExpenses + adjustment) - share;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                   Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(u.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      Text(
                        "${paidOnExpenses.toStringAsFixed(0)} ৳",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Share: ${share.toStringAsFixed(0)} ৳ ${adjustment != 0 ? '| Adj: ${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(0)} ৳' : ''}", 
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      Text(
                        "${balance >= 0 ? 'Credit: +' : 'Debt: '}${balance.toStringAsFixed(0)}",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: balance >= 0 ? Colors.green : Colors.red),
                      ),
                    ],
                  ),
                  const Divider(height: 12, thickness: 0.5),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          const Align(alignment: Alignment.centerLeft, child: Text("FINAL SETTLEMENT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(height: 8),
          if (settlementInstructions.isEmpty)
             const Text("All debts settled!", style: TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold))
          else
            ...settlementInstructions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.circle, size: 6, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(child: Text("${s.payerName} pays ${s.amount.toStringAsFixed(0)} ৳ to ${s.receiverName}", style: const TextStyle(fontSize: 13))),
                ],
              ),
            )),
          const SizedBox(height: 40),
          const Opacity(
            opacity: 0.3,
            child: Text("Thank you for using the App", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 10),
          _buildZigZagBottom(),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isBold ? color : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildZigZagBottom() {
    return Row(
      children: List.generate(20, (index) => Expanded(
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(5),
            ),
          ),
        ),
      )),
    );
  }
}
