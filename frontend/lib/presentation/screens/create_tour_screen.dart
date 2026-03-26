import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import '../../data/local/app_database.dart';
import 'package:frontend/data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';
import '../widgets/premium_card.dart';

class CreateTourScreen extends ConsumerStatefulWidget {
  final Tour? initialTour;
  const CreateTourScreen({super.key, this.initialTour});

  @override
  ConsumerState<CreateTourScreen> createState() => _CreateTourScreenState();
}

class _CreateTourScreenState extends ConsumerState<CreateTourScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memberController = TextEditingController();
  
  DateTimeRange? _selectedDateRange;
  final List<String> _additionalMembers = [];
  bool _isLoading = false;
  String _selectedPurpose = 'project'; 

  @override
  void initState() {
    super.initState();
    if (widget.initialTour != null) {
      _nameController.text = widget.initialTour!.name;
      _selectedPurpose = widget.initialTour!.purpose;
      if (widget.initialTour!.startDate != null && widget.initialTour!.endDate != null) {
        _selectedDateRange = DateTimeRange(
          start: widget.initialTour!.startDate!,
          end: widget.initialTour!.endDate!,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
    }
  }

  void _addMember() {
    final name = _memberController.text.trim();
    if (name.isNotEmpty) {
      if (!_additionalMembers.contains(name)) {
        setState(() {
          _additionalMembers.add(name);
          _memberController.clear();
        });
      }
    }
  }

  Future<void> _createTour() async {
    if (_formKey.currentState!.validate()) {
       setState(() => _isLoading = true);
       try {
         final db = ref.read(databaseProvider);
         User? currentUser = await ref.read(currentUserProvider.future);
         
         if (currentUser == null) throw Exception("Profile not found.");

         if (widget.initialTour == null) {
           final tourId = const Uuid().v4();
           const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
           final inviteCode = List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();

           await db.createTour(Tour(
               id: tourId,
               name: _nameController.text.trim(),
               startDate: _selectedDateRange?.start,
               endDate: _selectedDateRange?.end,
               inviteCode: inviteCode,
               createdBy: currentUser.id,
               purpose: _selectedPurpose,
               isSynced: false,
               updatedAt: DateTime.now()
           ));

           await db.into(db.tourMembers).insert(TourMember(
               tourId: tourId,
               userId: currentUser.id,
               status: 'active',
               role: 'admin',
               mealCount: 0.0,
               isSynced: false
           ));

           for (final memberName in _additionalMembers) {
             final memberId = const Uuid().v4();
             await db.createUser(User(
               id: memberId,
               name: memberName,
               phone: null,
               isMe: false,
               isSynced: false,
               updatedAt: DateTime.now(),
             ));
             await db.into(db.tourMembers).insert(TourMember(
               tourId: tourId,
               userId: memberId,
               status: 'active',
               role: 'viewer',
               mealCount: 0.0,
               isSynced: false,
             ));
           }
         } else {
           await db.createTour(widget.initialTour!.copyWith(
               name: _nameController.text.trim(),
               purpose: _selectedPurpose,
               startDate: drift.Value(_selectedDateRange?.start),
               endDate: drift.Value(_selectedDateRange?.end),
               isSynced: false,
               updatedAt: DateTime.now(),
           ));

           for (final memberName in _additionalMembers) {
             final memberId = const Uuid().v4();
             await db.createUser(User(
               id: memberId,
               name: memberName,
               phone: null,
               isMe: false,
               isSynced: false,
               updatedAt: DateTime.now(),
             ));
             await db.into(db.tourMembers).insert(TourMember(
               tourId: widget.initialTour!.id,
               userId: memberId,
               status: 'active',
               role: 'viewer',
               mealCount: 0.0,
               isSynced: false,
             ));
           }
         }
         
         if (mounted) {
           ref.read(syncServiceProvider).startSync(currentUser.id).catchError((e) => debugPrint(e.toString()));
           Navigator.pop(context);
         }
       } finally {
         if (mounted) setState(() => _isLoading = false);
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = PurposeConfig.getConfig(_selectedPurpose);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialTour == null ? 'Create ${config.label}' : 'Edit ${config.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: config.color,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: config.gradient)),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputLabel("Category", config.color),
                    DropdownButtonFormField<String>(
                      value: _selectedPurpose,
                      decoration: _getInputDecoration(hint: "Category", icon: config.icon, color: config.color),
                      items: ['project', 'tour', 'event', 'party', 'mess'].map((p) {
                        final pConfig = PurposeConfig.getConfig(p);
                        return DropdownMenuItem(value: p, child: Text(pConfig.label));
                      }).toList(),
                      onChanged: (value) { if (value != null) setState(() => _selectedPurpose = value); },
                    ),
                    const SizedBox(height: 24),
                    _buildInputLabel("Title", config.color),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      decoration: _getInputDecoration(hint: 'e.g. ${_getHintText(config.label)}', icon: Icons.edit_note_rounded, color: config.color),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),
                    _buildInputLabel("Dates", config.color),
                    InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(color: config.color.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, color: config.color, size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(
                              _selectedDateRange == null ? 'Timeline (Optional)' : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end)}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _selectedDateRange == null ? Colors.black38 : Colors.black87),
                            )),
                            if (_selectedDateRange != null) Icon(Icons.check_circle_rounded, color: config.color, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              _buildInputLabel("Add ${config.memberLabel}s", config.color),
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _memberController,
                            decoration: _getInputDecoration(hint: 'Name', icon: Icons.person_add_rounded, color: config.color, dense: true),
                            onFieldSubmitted: (_) => _addMember(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filled(
                          onPressed: _addMember,
                          icon: const Icon(Icons.add),
                          style: IconButton.styleFrom(
                            backgroundColor: config.color,
                            minimumSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                    if (_additionalMembers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _additionalMembers.asMap().entries.map((entry) {
                          return Chip(
                            label: Text(entry.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onDeleted: () => setState(() => _additionalMembers.removeAt(entry.key)),
                            backgroundColor: config.color.withOpacity(0.1),
                            side: BorderSide(color: config.color.withOpacity(0.1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 48),
              SizedBox(
                height: 64,
                child: FilledButton(
                    onPressed: _isLoading ? null : _createTour,
                    style: FilledButton.styleFrom(
                      backgroundColor: config.color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: config.color.withOpacity(0.5)
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : Text(widget.initialTour == null ? 'Launch ${config.label} 🚀' : 'Save Changes ✨', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label, Color color) {
    return Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.2)));
  }

  InputDecoration _getInputDecoration({required String hint, required IconData icon, required Color color, bool dense = false}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: color, size: 20),
      filled: true,
      fillColor: color.withOpacity(0.05),
      contentPadding: dense ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) : const EdgeInsets.all(20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: color, width: 2)),
    );
  }

  String _getHintText(String label) {
    switch (label.toLowerCase()) {
      case 'party': return 'BBQ Night';
      case 'mess': return 'Monthly Mess';
      case 'project': return 'Mobile App';
      default: return 'Sajek Valley Trip';
    }
  }
}
