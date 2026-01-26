import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/app_database.dart';
import '../../data/providers/app_providers.dart';
import '../../main.dart';
import 'tour_list_screen.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  final String? inviteCode;
  const WelcomeScreen({super.key, this.inviteCode});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  String _selectedPurpose = 'party'; 
  bool _isLoading = false;

  final List<Map<String, dynamic>> _purposes = [
    {'id': 'party', 'name': 'Party', 'icon': Icons.outdoor_grill_rounded},
    {'id': 'tour', 'name': 'Tour', 'icon': Icons.beach_access_rounded},
    {'id': 'mess', 'name': 'Mess', 'icon': Icons.home_work_rounded},
    {'id': 'event', 'name': 'Event', 'icon': Icons.celebration_rounded},
    {'id': 'office', 'name': 'Work', 'icon': Icons.business_center_rounded},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.inviteCode != null) {
      _inviteCodeController.text = widget.inviteCode!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }


  Future<void> _createProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    final enteredInviteCode = _inviteCodeController.text.trim().toUpperCase();

    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final userId = const Uuid().v4();
      
      final newUser = User(
        id: userId,
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        purpose: enteredInviteCode.isNotEmpty ? 'tour' : _selectedPurpose,
        isMe: true,
        isSynced: false,
        updatedAt: DateTime.now(),
      );

      await db.createUser(newUser);
      
      // Force riverpod to pick up the new user immediately
      ref.invalidate(currentUserProvider);
      await ref.read(currentUserProvider.future);
      
      // If there's an invite code, join immediately
      if (enteredInviteCode.isNotEmpty) {
        await ref.read(syncServiceProvider).joinByInvite(
          enteredInviteCode,
          userId,
          _nameController.text.trim()
        );
      }
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TourListScreen()),
        );
        if (enteredInviteCode.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile created and joined successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.startsWith("Exception: ")) {
          errorMsg = errorMsg.replaceFirst("Exception: ", "");
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $errorMsg"), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.teal.shade500, Colors.teal.shade900],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(Icons.auto_awesome, size: 60, color: Colors.teal.shade700),
                  ),
                  const SizedBox(height: 16),
                  const Text("Tour Manager", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Text("The Classroom for Expenses", style: TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 32),

                  Card(
                    elevation: 12,
                    shadowColor: Colors.black.withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Center(child: Text("Basic Info", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: "Profile Name",
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: "Email Address",
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 24),
                            
                            // PURPOSE OR JOIN WITH CODE
                            const Text("What are you doing today?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 12),
                            
                            // Tabs or Choice Chip for Purpose
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _purposes.map((p) => _buildPurposeChip(p)).toList(),
                            ),
                            
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: Text("OR", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                            ),
                            
                            TextFormField(
                              controller: _inviteCodeController,
                              decoration: InputDecoration(
                                labelText: "Join with Code",
                                hintText: "Enter 6-digit code",
                                prefixIcon: const Icon(Icons.vpn_key_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                counterText: "", // Hide character counter
                                fillColor: Colors.blue.shade50,
                                filled: true,
                              ),
                              maxLength: 6,
                              textCapitalization: TextCapitalization.characters,
                            ),

                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _isLoading ? null : () => _createProfile(),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  backgroundColor: Colors.teal.shade700,
                                ),
                                child: _isLoading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text("Start Now", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPurposeChip(Map<String, dynamic> p) {
    bool isSelected = _selectedPurpose == p['id'] && _inviteCodeController.text.isEmpty;
    return ChoiceChip(
      avatar: Icon(p['icon'], size: 16, color: isSelected ? Colors.white : Colors.grey),
      label: Text(p['name']),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
           setState(() {
              _selectedPurpose = p['id'];
              _inviteCodeController.clear();
           });
        }
      },
      selectedColor: Colors.teal,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
    );
  }
}


