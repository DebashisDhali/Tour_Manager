import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../data/local/app_database.dart';
import '../../data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';

class CreateTourScreen extends ConsumerStatefulWidget {
  const CreateTourScreen({super.key});

  @override
  ConsumerState<CreateTourScreen> createState() => _CreateTourScreenState();
}

class _CreateTourScreenState extends ConsumerState<CreateTourScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _userNameController = TextEditingController();
  final _memberController = TextEditingController();
  
  DateTimeRange? _selectedDateRange;
  final List<String> _additionalMembers = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _userNameController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member already added!')),
        );
      }
    }
  }

  void _removeMember(int index) {
    setState(() {
      _additionalMembers.removeAt(index);
    });
  }

  Future<void> _createTour() async {
    if (_formKey.currentState!.validate()) {
       setState(() => _isLoading = true);
       try {
         final db = ref.read(databaseProvider);
         
         // 1. Try to get user from provider stream
         User? currentUser = await ref.read(currentUserProvider.future);
         
         // 2. Double-check: Direct DB query if provider returned null (redundancy)
         if (currentUser == null) {
           final allUsers = await db.getAllUsers();
           if (allUsers.isNotEmpty) {
             currentUser = allUsers.first;
           }
         }

         if (currentUser == null) {
           throw Exception("Profile not found. Please restart the app or set up your profile.");
         }

         final tourId = const Uuid().v4();
         
         // Helper to generate 6-char alphanumeric code
         const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No O, 0, I, 1
         final inviteCode = List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();

         // 3. Create Tour
         await db.createTour(Tour(
             id: tourId,
             name: _nameController.text.trim(),
             startDate: _selectedDateRange?.start,
             endDate: _selectedDateRange?.end,
             inviteCode: inviteCode,
             createdBy: currentUser.id,
             isSynced: false,
             updatedAt: DateTime.now()
         ));


         // 3. Add self to tour
         await db.into(db.tourMembers).insert(TourMember(
             tourId: tourId,
             userId: currentUser.id,
             isSynced: false
         ));

         // 4. Create and add additional members
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
             isSynced: false,
           ));
         }
         
         if (mounted) Navigator.pop(context);
       } catch (e) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
           );
         }
       } finally {
         if (mounted) setState(() => _isLoading = false);
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final config = PurposeConfig.getConfig(userAsync.value?.purpose);

    return Scaffold(
      appBar: AppBar(
        title: Text('New ${config.label} Setup'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("${config.label} Details"),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                    labelText: '${config.label} Name',
                    hintText: 'e.g. ${config.label == 'Party' ? 'BBQ Night' : 'Sajek Valley'}',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    prefixIcon: Icon(config.icon)
                ),
                validator: (v) => v == null || v.isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 16),
              
              // Date Selection
              InkWell(
                onTap: _selectDateRange,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, color: Colors.teal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDateRange == null
                              ? 'Select Date Range (Optional)'
                              : '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: _selectedDateRange == null ? Colors.grey.shade700 : Colors.black,
                          ),
                        ),
                      ),
                      if (_selectedDateRange != null)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => setState(() => _selectedDateRange = null),
                        ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              _buildSectionTitle("Add Members"),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _memberController,
                      decoration: InputDecoration(
                        labelText: 'Friend\'s Name',
                        hintText: 'Add friend',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        prefixIcon: const Icon(Icons.person_add_outlined),
                      ),
                      onFieldSubmitted: (_) => _addMember(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _addMember,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(56, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_additionalMembers.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _additionalMembers.asMap().entries.map((entry) {
                    return Chip(
                      label: Text(entry.value),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => _removeMember(entry.key),
                      backgroundColor: Colors.teal.shade50,
                      side: BorderSide(color: Colors.teal.shade100),
                    );
                  }).toList(),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("No friends added yet. You can add them later too!", 
                    style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                ),
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: _isLoading ? null : _createTour,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Text('Launch Tour 🚀', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
    );
  }
}


