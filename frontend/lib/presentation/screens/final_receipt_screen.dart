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
    Map<String, double> mealCounts,
    List<models.ProgramIncome> incomes,
  ) async {
    final calculator = SettlementCalculator();
    final balanceMap = calculator.getFullBalances(
      expenses: expenses,
      splits: splits,
      expensePayers: tourPayers,
      users: users,
      previousSettlements: previousSettlements,
      purpose: purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );
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
                  child: pw.Text('${config.label.toUpperCase()} COST RECEIPT',
                      style: pw.TextStyle(
                          fontSize: 24, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(tour.name,
                      style: const pw.TextStyle(fontSize: 18)),
                ),
                pw.Center(
                  child: pw.Text(
                    tour.startDate == null
                        ? 'Active Period'
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
                    pw.Text('Total ${config.label} Cost:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('${totalCost.toStringAsFixed(0)} BDT'),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text('MEMBER CONTRIBUTIONS',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Name', 'Paid', 'Settled', 'Share', 'Balance'],
                  cellAlignment: pw.Alignment.centerRight,
                  headerAlignment: pw.Alignment.centerRight,
                  data: users.map<List<String>>((u) {
                    final nid = u.id.toLowerCase();
                    final balanceDetails = balanceMap[nid] ?? balanceMap[u.id];
                    final paidOnExpenses = balanceDetails?.paid ?? 0.0;
                    final share = balanceDetails?.share ?? 0.0;
                    final adjustment = balanceDetails?.settled ?? 0.0;
                    final balance = balanceDetails?.net ?? 0.0;

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
                pw.Text('SETTLEMENT PLAN',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (settlementInstructions.isEmpty)
                  pw.Text('• All debts settled!')
                else
                  ...settlementInstructions.map((s) => pw.Text(
                      '• ${s.payerName} pays ${s.amount.toStringAsFixed(0)} to ${s.receiverName}')),
                pw.Spacer(),
                pw.Divider(),
                pw.Center(
                  child: pw.Text('Generated by Manager',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey)),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
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
    Map<String, double> mealCounts,
    List<models.ProgramIncome> incomes,
  ) async {
    final config = PurposeConfig.getConfig(purpose);
    final pdfBytes = await _generatePdfBytes(
        tour,
        users,
        expenses,
        splits,
        tourPayers,
        previousSettlements,
        settlementInstructions,
        purpose,
        mealCounts,
        incomes);

    final fileName = "${tour.name.replaceAll(' ', '_')}_Receipt.pdf";

    await ExportDelegate.shareFile(pdfBytes, fileName,
        subject: '${config.label} Cost Receipt: ${tour.name}');
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
    Map<String, double> mealCounts,
    List<models.ProgramIncome> incomes,
  ) async {
    final calculator = SettlementCalculator();
    final balanceMap = calculator.getFullBalances(
      expenses: expenses,
      splits: splits,
      expensePayers: tourPayers,
      users: users,
      previousSettlements: previousSettlements,
      purpose: purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );
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
                    child: pw.Text('${config.label.toUpperCase()} COST RECEIPT',
                        style: pw.TextStyle(
                            fontSize: 24, fontWeight: pw.FontWeight.bold))),
                pw.SizedBox(height: 8),
                pw.Center(
                    child: pw.Text(tour.name,
                        style: const pw.TextStyle(fontSize: 18))),
                pw.Center(
                    child: pw.Text(
                        tour.startDate == null
                            ? 'Active'
                            : '${DateFormat('MMM dd, yyyy').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}',
                        style: const pw.TextStyle(fontSize: 12))),
                pw.SizedBox(height: 24),
                pw.Divider(),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total ${config.label} Cost:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('${totalCost.toStringAsFixed(0)} BDT'),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text('MEMBER CONTRIBUTIONS',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Name', 'Paid', 'Settled', 'Share', 'Balance'],
                  cellAlignment: pw.Alignment.centerRight,
                  headerAlignment: pw.Alignment.centerRight,
                  data: users.map<List<String>>((u) {
                    final nid = u.id.toLowerCase();
                    final balanceDetails = balanceMap[nid] ?? balanceMap[u.id];
                    final paidOnExpenses = balanceDetails?.paid ?? 0.0;
                    final share = balanceDetails?.share ?? 0.0;
                    final adjustment = balanceDetails?.settled ?? 0.0;
                    final balance = balanceDetails?.net ?? 0.0;

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
                pw.Text('SETTLEMENT PLAN',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (settlementInstructions.isEmpty)
                  pw.Text('• All debts settled!')
                else
                  ...settlementInstructions.map((s) => pw.Text(
                      '• ${s.payerName} pays ${s.amount.toStringAsFixed(0)} to ${s.receiverName}')),
                pw.Spacer(),
                pw.Divider(),
                pw.Center(
                    child: pw.Text('Generated by Manager',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey))),
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

    if (tourAsync.isLoading ||
        usersAsync.isLoading ||
        expensesAsync.isLoading ||
        splitsAsync.isLoading ||
        settlementsAsync.isLoading ||
        payersAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tour = tourAsync.value;
    final users = usersAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];
    final splits = splitsAsync.value ?? [];
    final previousSettlements = settlementsAsync.value ?? [];
    final tourPayers = payersAsync.value ?? [];
    final tourMembers = ref.watch(tourMembersProvider(tourId)).value ?? [];
    final incomes = ref.watch(tourIncomesProvider(tourId)).value ?? [];

    if (tour == null)
      return const Scaffold(body: Center(child: Text("Project not found")));

    final mealCounts = {for (var m in tourMembers) m.user.id: m.mealCount};
    final myId = ref.watch(currentUserProvider).value?.id;
    final myMember = tourMembers.where((m) => m.user.id == myId).firstOrNull;
    final isMember = myMember != null;

    final calculator = SettlementCalculator();
    final settlementInstructions = calculator.calculate(
      expenses,
      splits,
      tourPayers,
      users,
      previousSettlements,
      purpose: tour.purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("${PurposeConfig.getConfig(tour.purpose).label} Statement"),
        actions: [
          Tooltip(
            message: isMember ? '' : 'Only members can share receipts',
            child: IconButton(
              icon: const Icon(Icons.share),
              onPressed: isMember
                  ? () => _shareReceipt(
                      tour,
                      users,
                      expenses,
                      splits,
                      tourPayers,
                      previousSettlements,
                      settlementInstructions,
                      tour.purpose,
                      mealCounts,
                      incomes)
                  : null,
            ),
          ),
          Tooltip(
            message: isMember ? '' : 'Only members can print receipts',
            child: IconButton(
              icon: const Icon(Icons.print),
              onPressed: isMember
                  ? () => _printReceipt(
                      tour,
                      users,
                      expenses,
                      splits,
                      tourPayers,
                      previousSettlements,
                      settlementInstructions,
                      tour.purpose,
                      mealCounts,
                      incomes)
                  : null,
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildReceiptPaper(
                context,
                tour,
                users,
                expenses,
                splits,
                tourPayers,
                previousSettlements,
                settlementInstructions,
                tour.purpose,
                mealCounts,
                incomes),
            const SizedBox(height: 40),
            if (!isMember)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Only members can download and share receipts',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _shareReceipt(
                            tour,
                            users,
                            expenses,
                            splits,
                            tourPayers,
                            previousSettlements,
                            settlementInstructions,
                            tour.purpose,
                            mealCounts,
                            incomes),
                        icon: const Icon(Icons.share),
                        label: const Text("Share"),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _printReceipt(
                            tour,
                            users,
                            expenses,
                            splits,
                            tourPayers,
                            previousSettlements,
                            settlementInstructions,
                            tour.purpose,
                            mealCounts,
                            incomes),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text("Print"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
    Map<String, double> mealCounts,
    List<models.ProgramIncome> incomes,
  ) {
    final calculator = SettlementCalculator();
    final balanceMap = calculator.getFullBalances(
      expenses: expenses,
      splits: splits,
      expensePayers: tourPayers,
      users: users,
      previousSettlements: previousSettlements,
      purpose: purpose,
      mealCounts: mealCounts,
      incomes: incomes,
    );
    final totalCost = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final config = PurposeConfig.getConfig(purpose);
    final isMess = purpose?.toLowerCase() == 'mess';

    // Mess-specific calculations (Aligned with MessSettlementCalculator)
    double totalMealCost = 0.0;
    double totalFixedCost = 0.0;
    double standardMealCost = 0.0;
    double standardFixedCost = 0.0;

    final splitExpenseIds = splits.map((s) => s.expenseId.toLowerCase()).toSet();

    if (isMess) {
      for (var e in expenses) {
        final category = e.category.toLowerCase().trim();
        final type = e.messCostType?.toLowerCase().trim();
        final isRent = category == 'rent' || 
                       type == 'fixed' || 
                       category == 'maid' || 
                       category == 'wifi' || 
                       category == 'others';

        bool isCustomSplit = splitExpenseIds.contains(e.id.toLowerCase());
        
        // Ignore auto-generated equal splits for Bazar expenses
        if (isCustomSplit && !isRent) {
          final eSplits = splits.where((s) => s.expenseId.toLowerCase() == e.id.toLowerCase()).toList();
          if (eSplits.isNotEmpty) {
            final firstAmount = eSplits.first.amount;
            if (eSplits.every((s) => (s.amount - firstAmount).abs() < 0.01)) {
              isCustomSplit = false;
            }
          }
        }

        if (isRent) {
          totalFixedCost += e.amount;
          if (!isCustomSplit) standardFixedCost += e.amount;
        } else {
          totalMealCost += e.amount;
          if (!isCustomSplit) standardMealCost += e.amount;
        }
      }
    }

    final totalMeals = mealCounts.values.fold(0.0, (s, c) => s + c);
    final mealRate = totalMeals > 0 ? standardMealCost / totalMeals : 0.0;
    final fixedPerPerson = users.isNotEmpty ? standardFixedCost / users.length : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          Text(isMess ? "MESS MONTHLY STATEMENT" : "FINAL RECEIPT",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 4),
          const Divider(),
          const SizedBox(height: 12),
          Text(tour.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(
            tour.startDate == null
                ? 'Active Period'
                : '${DateFormat('MMM dd, yyyy').format(tour.startDate!)} — ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          if (isMess) ...[
            // ── MESS SUMMARY METRICS ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: _buildMetricTile("Total Bazar", "৳${totalMealCost.toStringAsFixed(0)}", Colors.orange)),
                    Expanded(child: _buildMetricTile("Total Rent", "৳${totalFixedCost.toStringAsFixed(0)}", Colors.teal)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _buildMetricTile("Total Meals", totalMeals.toStringAsFixed(1), Colors.blue)),
                    Expanded(child: _buildMetricTile("Meal Rate", "৳${mealRate.toStringAsFixed(2)}/meal", Colors.purple)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // ── MESS MEMBER TABLE ──
            const Align(
                alignment: Alignment.centerLeft,
                child: Text("MEMBER BREAKDOWN",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5))),
            const SizedBox(height: 8),
            Table(
              border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade100, width: 0.5), bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.0),
                2: FlexColumnWidth(1.2),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1.2),
                5: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.teal.shade50),
                  children: [
                    _buildTableHeaderCell("Name", Alignment.centerLeft),
                    _buildTableHeaderCell("Meals", Alignment.center),
                    _buildTableHeaderCell("Bazar ৳", Alignment.centerRight),
                    _buildTableHeaderCell("Rent ৳", Alignment.centerRight),
                    _buildTableHeaderCell("Paid ৳", Alignment.centerRight),
                    _buildTableHeaderCell("Balance", Alignment.centerRight),
                  ],
                ),
                ...users.map((u) {
                  final nid = u.id.toLowerCase();
                  final bd = balanceMap[nid] ?? balanceMap[u.id];
                  final meals = mealCounts[u.id] ?? mealCounts[nid] ?? 0.0;
                  
                  double bazarShare = 0.0;
                  double rentShare = 0.0;
                  
                  if (bd != null) {
                    for (var item in bd.items) {
                      final title = item.title.toLowerCase();
                      final isMealCharge = title.contains("meal charge") || title.contains("bazar rounding") || title.contains("bazar (split)") || title.contains("meal (split)");
                      final isRentCharge = title.contains("rent share") || title.contains("rent rounding") || title.contains("rent (split)") || title.contains("fixed (split)") || title.contains("vara");
                      
                      if (isMealCharge) {
                        bazarShare += item.amount;
                      } else if (isRentCharge) {
                        rentShare += item.amount;
                      }
                    }
                  }

                  final paid = bd?.paid ?? 0.0;
                  final balance = bd?.net ?? 0.0;
                  return TableRow(children: [
                    _buildTableCell(u.name, Alignment.centerLeft, isBold: true),
                    _buildTableCell(meals.toStringAsFixed(1), Alignment.center),
                    _buildTableCell(bazarShare.toStringAsFixed(0), Alignment.centerRight),
                    _buildTableCell(rentShare.toStringAsFixed(0), Alignment.centerRight),
                    _buildTableCell(paid.toStringAsFixed(0), Alignment.centerRight),
                    _buildTableCell(
                      "${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)}",
                      Alignment.centerRight,
                      isBold: true,
                      color: balance.abs() < 0.5 ? Colors.grey : (balance > 0 ? Colors.green : Colors.red),
                    ),
                  ]);
                }),
              ],
            ),
            const SizedBox(height: 20),
            // ── EXPENSE BREAKDOWN ──
            const Align(
                alignment: Alignment.centerLeft,
                child: Text("EXPENSE BREAKDOWN",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5))),
            const SizedBox(height: 8),
            ...expenses.map((e) {
              final category = e.category.toLowerCase().trim();
              final type = e.messCostType?.toLowerCase().trim();
              final isRent = category == 'rent' || 
                             type == 'fixed' || 
                             category == 'maid' || 
                             category == 'wifi' || 
                             category == 'others' ||
                             category.contains("vara");
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: !isRent ? Colors.orange.shade50 : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      !isRent ? "BAZAR" : "RENT",
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: !isRent ? Colors.orange.shade700 : Colors.teal.shade700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.title, style: const TextStyle(fontSize: 12))),
                  Text("৳${e.amount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              );
            }),
            const Divider(height: 20),
            _buildRow("Total", "৳${totalCost.toStringAsFixed(0)}", config.color, isBold: true),
          ] else ...[
            _buildRow("Total ${config.label} Cost", "${totalCost.toStringAsFixed(0)} ৳", config.color, isBold: true),
            _buildRow("Total Members", "${users.length}", config.color),
            const SizedBox(height: 24),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text("MEMBER CONTRIBUTIONS",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5))),
            const SizedBox(height: 12),
            Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade100, width: 0.5),
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              columnWidths: const {
                0: FlexColumnWidth(2.5),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(1.5),
                4: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade50),
                  children: [
                    _buildTableHeaderCell("Name", Alignment.centerLeft),
                    _buildTableHeaderCell("Paid", Alignment.centerRight),
                    _buildTableHeaderCell("Settled", Alignment.centerRight),
                    _buildTableHeaderCell("Share", Alignment.centerRight),
                    _buildTableHeaderCell("Balance", Alignment.centerRight),
                  ],
                ),
                ...users.map((u) {
                  final nid = u.id.toLowerCase();
                  final balanceDetails = balanceMap[nid] ?? balanceMap[u.id];
                  final balance = balanceDetails?.net ?? 0.0;
                  final share = balanceDetails?.share ?? 0.0;
                  final paidOnExpenses = balanceDetails?.paid ?? 0.0;
                  final adjustment = balanceDetails?.settled ?? 0.0;
                  return TableRow(children: [
                    _buildTableCell(u.name, Alignment.centerLeft, isBold: true),
                    _buildTableCell(paidOnExpenses.toStringAsFixed(0), Alignment.centerRight),
                    _buildTableCell(
                      "${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(0)}",
                      Alignment.centerRight,
                      color: adjustment == 0 ? Colors.grey : (adjustment > 0 ? Colors.green : Colors.orange),
                    ),
                    _buildTableCell(share.toStringAsFixed(0), Alignment.centerRight),
                    _buildTableCell(
                      "${balance >= 0 ? '+' : ''}${balance.toStringAsFixed(0)}",
                      Alignment.centerRight,
                      isBold: true,
                      color: balance.abs() < 0.1 ? Colors.grey : (balance > 0 ? Colors.green : Colors.red),
                    ),
                  ]);
                }),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text("FINAL SETTLEMENT",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(height: 8),
          if (settlementInstructions.isEmpty)
            const Text("All debts settled!",
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green,
                    fontWeight: FontWeight.bold))
          else
            ...settlementInstructions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, size: 6, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              "${s.payerName} pays ${s.amount.toStringAsFixed(0)} ৳ to ${s.receiverName}",
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          const SizedBox(height: 40),
          const Opacity(
            opacity: 0.3,
            child: Text("Thank you for using Manager",
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 10),
          _buildZigZagBottom(),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isBold ? color : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _buildZigZagBottom() {
    return Row(
      children: List.generate(
          20,
          (index) => Expanded(
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

  Widget _buildTableHeaderCell(String value, Alignment alignment) {
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: alignment,
      child: Text(value,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
    );
  }

  Widget _buildTableCell(String value, Alignment alignment,
      {bool isBold = false, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      alignment: alignment,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}
