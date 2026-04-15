import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/local/app_database.dart';
import 'package:frontend/data/providers/app_providers.dart';
import 'package:frontend/data/providers/theme_provider.dart';
import 'login_screen.dart';

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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.isMe ? "My Profile" : "Member Profile", 
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (widget.isMe)
            IconButton(
              icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_note_rounded, color: Colors.blue.shade700),
              onPressed: () => setState(() => _isEditing = !_isEditing),
            )
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _isEditing ? _buildEditForm() : _buildViewDetails(),
            ),
            const SizedBox(height: 40),
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

    return Column(
      children: [
        const SizedBox(height: 20),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.blue.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 58,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 54,
                backgroundColor: Colors.blue.shade600,
                backgroundImage: backgroundImage,
                child: backgroundImage == null ? Text(
                  _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : "?",
                  style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.w900),
                ) : null,
              ),
            ),
            if (_isEditing)
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Icon(Icons.camera_alt_rounded, color: Colors.blue.shade700, size: 20),
                  ),
                ),
              )
          ],
        ),

        const SizedBox(height: 20),
        if (!_isEditing) ...[
          Text(
            _nameController.text,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(
            _emailController.text.isNotEmpty ? _emailController.text : "@anonymous",
            style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade500, fontWeight: FontWeight.w500),
          ),
        ] else
          Text("Personalize Profile", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.blue.shade700, fontSize: 16)),
      ],
    );
  }

  Widget _buildViewDetails() {
    return Column(
      children: [
        _buildSectionCard(
          title: "Account Details",
          items: [
            _buildInfoTile(Icons.phone_rounded, "Phone Number", _phoneController.text.isNotEmpty ? _phoneController.text : "Not verified", Colors.green),
            _buildInfoTile(Icons.alternate_email_rounded, "Email Address", _emailController.text.isNotEmpty ? _emailController.text : "Not verified", Colors.blue),
            _buildInfoTile(Icons.fingerprint_rounded, "Unique Identification", widget.user.id, Colors.purple),
            _buildInfoTile(Icons.cloud_done_rounded, "Synchronization", widget.user.isSynced ? "Cloud Verified" : "Offline Mode", Colors.orange),
          ],
        ),
        
        const SizedBox(height: 20),
        if (widget.isMe) ...[
          _buildSectionCard(
            title: "App Experience",
            items: [
               ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(ref.watch(themeProvider) == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: Colors.indigo, size: 20),
                ),
                title: const Text("Dark Theme", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                trailing: Switch.adaptive(
                  value: ref.watch(themeProvider) == ThemeMode.dark,
                  activeColor: Colors.indigo,
                  onChanged: (val) {
                    ref.read(themeProvider.notifier).setTheme(val ? ThemeMode.dark : ThemeMode.light);
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _showLogoutConfirmation,
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade600,
                elevation: 0,
                side: BorderSide(color: Colors.red.shade100, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text("Return", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blueGrey.shade400,
            ),
          ),
        )
      ],
    );
  }

  Future<void> _showLogoutConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Confirm Sign Out", style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("Are you certain you want to end your current session?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Stay", style: TextStyle(color: Colors.blueGrey.shade600, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: Text("Sign Out", style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w900))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authServiceProvider).logout();
      ref.invalidate(currentUserProvider);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildSectionCard({required String title, required List<Widget> items}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade400, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade400)),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.blueGrey.shade800)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Column(
      children: [
        _buildModernTextField(_nameController, "Display Name", Icons.person_outline_rounded),
        const SizedBox(height: 20),
        _buildModernTextField(_phoneController, "Contact Number", Icons.phone_android_rounded, type: TextInputType.phone),
        const SizedBox(height: 20),
        _buildModernTextField(_emailController, "Primary Email", Icons.email_outlined, type: TextInputType.emailAddress),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              elevation: 5,
              shadowColor: Colors.blue.withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: _isLoading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
              : const Text("Commit Changes", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() => _isEditing = false),
          child: Text("Discard Changes", style: TextStyle(color: Colors.blueGrey.shade400, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildModernTextField(TextEditingController controller, String label, IconData icon, {TextInputType type = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade700)),
        ),
        TextFormField(
          controller: controller,
          keyboardType: type,
          style: const TextStyle(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20, color: Colors.blue.shade600),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.blueGrey.shade200, width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.blue.shade600, width: 2)),
            contentPadding: const EdgeInsets.all(18),
          ),
        ),
      ],
    );
  }
}
