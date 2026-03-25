import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/local/app_database.dart';
import 'package:frontend/data/providers/app_providers.dart';
import 'welcome_screen.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final User user;
  final bool isMe;
  
  const UserProfileScreen({super.key, required this.user, this.isMe = false});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}



class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _avatarController; // This will now hold base64 or URL
  bool _isEditing = false;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    
    // Smart name resolution: If name is Unknown but email exists, use email username
    String displayName = widget.user.name;
    if ((displayName.isEmpty || displayName.toLowerCase() == 'unknown') && 
        widget.user.email != null && widget.user.email!.contains('@')) {
       final parts = widget.user.email!.split('@');
       if (parts.isNotEmpty && parts[0].isNotEmpty) {
         displayName = parts[0][0].toUpperCase() + parts[0].substring(1);
       }
    }

    _nameController = TextEditingController(text: displayName);
    _phoneController = TextEditingController(text: widget.user.phone ?? "");
    _emailController = TextEditingController(text: widget.user.email ?? "");
    _avatarController = TextEditingController(text: widget.user.avatarUrl ?? "");
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);
        setState(() {
          _avatarController.text = "data:image/png;base64,$base64Image";
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error picking image: $e")));
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final updatedUser = widget.user.copyWith(
        name: _nameController.text.trim(),
        phone: Value(_phoneController.text.isEmpty ? null : _phoneController.text.trim()),
        email: Value(_emailController.text.isEmpty ? null : _emailController.text.trim()),
        avatarUrl: Value(_avatarController.text.isEmpty ? null : _avatarController.text.trim()),
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      
      await db.createUser(updatedUser);
      setState(() {
        _isEditing = false;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully!")));
      
      if (widget.isMe) {
        ref.invalidate(currentUserProvider);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isMe ? "My Profile" : "Member Profile"),
        elevation: 0,
        actions: [
          if (widget.isMe)
            IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit_note),
              onPressed: () => setState(() => _isEditing = !_isEditing),
            )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _isEditing ? _buildEditForm() : _buildViewDetails(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final photoData = _avatarController.text;
    ImageProvider? backgroundImage;
    
    if (photoData.isNotEmpty) {
      if (photoData.startsWith("data:image")) {
        final base64String = photoData.split(',').last;
        backgroundImage = MemoryImage(base64Decode(base64String));
      } else {
        backgroundImage = NetworkImage(photoData);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.teal,
                backgroundImage: backgroundImage,
                child: backgroundImage == null ? Text(
                  _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : "?",
                  style: const TextStyle(fontSize: 50, color: Colors.white, fontWeight: FontWeight.bold),
                ) : null,
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      backgroundColor: Colors.teal.shade700,
                      radius: 20,
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                )
            ],
          ),

          const SizedBox(height: 16),
          if (!_isEditing) ...[
            Text(
              _nameController.text,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _emailController.text.isNotEmpty ? _emailController.text : "No email added",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ] else
            const Text("Editing Profile", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        ],
      ),
    );
  }

  Widget _buildViewDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Account Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildDetailItem(Icons.phone_outlined, "Phone Number", _phoneController.text.isNotEmpty ? _phoneController.text : "Not provided"),
        _buildDetailItem(Icons.email_outlined, "Email", _emailController.text.isNotEmpty ? _emailController.text : "Not provided"),
        _buildDetailItem(Icons.badge_outlined, "User ID", widget.user.id),
        _buildDetailItem(Icons.sync, "Sync Status", widget.user.isSynced ? "Synced with Cloud" : "Local Only"),
        const SizedBox(height: 40),
        const SizedBox(height: 24),
        if (widget.isMe) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Logout"),
                    content: const Text("Are you sure you want to logout?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Logout", style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );

                if (confirm == true) {
                  await ref.read(authServiceProvider).logout();
                  ref.invalidate(currentUserProvider);
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                      (route) => false,
                    );
                  }
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text("Go Back"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Edit Information", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildTextField(_nameController, "Full Name", Icons.person_outline),
        const SizedBox(height: 16),
        _buildTextField(_phoneController, "Phone Number", Icons.phone_outlined, type: TextInputType.phone),
        const SizedBox(height: 16),
        _buildTextField(_emailController, "Email Address", Icons.email_outlined, type: TextInputType.emailAddress),
        const SizedBox(height: 16),
        // Removed manual URL field as we now use Device Picking
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _saveProfile,
            icon: _isLoading 
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
              : const Icon(Icons.save_outlined),
            label: const Text("Save Changes"),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => setState(() => _isEditing = false),
            child: const Text("Cancel"),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, color: Colors.teal, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
