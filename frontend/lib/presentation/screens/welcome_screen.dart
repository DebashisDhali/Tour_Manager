import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/app_database.dart';
import 'package:frontend/data/providers/app_providers.dart';
import '../widgets/premium_card.dart';
import '../../domain/logic/purpose_config.dart';
import 'tour_list_screen.dart';
import 'login_screen.dart';

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
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  String _selectedPurpose = 'project'; 
  bool _isLoading = false;
  bool _obscurePassword = true;

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
    _phoneController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }


  Future<void> _createProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    final enteredInviteCode = _inviteCodeController.text.trim().toUpperCase();

    setState(() => _isLoading = true);
    try {
      // 1. Register on Server first to get token
      await ref.read(authServiceProvider).register(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _phoneController.text.trim(),
        _passwordController.text.trim(),
      );

      // 2. Get the newly created user (AuthService._saveAuthData saves it locally with isMe: true)
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null) throw Exception("Failed to retrieve profile after registration.");
      
      // 3. Sync profile metadata
      await ref.read(syncServiceProvider).startSync(currentUser.id).catchError((e) => debugPrint("Profile Sync failed: $e"));

      // 4. If there's an invite code, join immediately
      if (enteredInviteCode.isNotEmpty) {
        await ref.read(syncServiceProvider).joinByInvite(
          enteredInviteCode,
          currentUser.id,
          currentUser.name,
          email: currentUser.email,
          purpose: _selectedPurpose,
        );
      }
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TourListScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString().replaceAll('Exception: ', '')}"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeConfig = PurposeConfig.getConfig(_selectedPurpose);

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(gradient: activeConfig.gradient),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  children: [
                    // Header Section
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, size: 48, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Group Ledger",
                            style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
                          ),
                          Text(
                            "Professional expense tracking for teams",
                            style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.8), letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 48),

                    // Main Form Card
                    PremiumCard(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Get Started",
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 24),
                            
                            _buildTextField(
                              controller: _nameController,
                              label: "Your Name",
                              icon: Icons.person_rounded,
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _emailController,
                              label: "Email Address",
                              icon: Icons.email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: "Phone Number (Searchable)",
                              icon: Icons.phone_rounded,
                              keyboardType: TextInputType.phone,
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _passwordController,
                              label: "Password",
                              icon: Icons.lock_rounded,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (v) => v != null && v.length < 6 ? "Min 6 characters" : (v == null || v.isEmpty ? "Required" : null),
                            ),
                            
                            const SizedBox(height: 32),
                            Text(
                              "What's the occasion?",
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                            ),
                            const SizedBox(height: 16),
                            
                            // Purpose Selection
                            SizedBox(
                              height: 90,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: PurposeConfig.allConfigs.length,
                                itemBuilder: (context, index) => _buildPurposeItem(PurposeConfig.allConfigs[index]),
                              ),
                            ),
                            
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text("OR JOIN", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w800)),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                            ),
                            
                            _buildTextField(
                              controller: _inviteCodeController,
                              label: "Invite Code",
                              icon: Icons.qr_code_rounded,
                              hint: "ABC-123",
                              maxLength: 6,
                              filled: true,
                              fillColor: activeConfig.color.withOpacity(0.05),
                              borderColor: activeConfig.color.withOpacity(0.1),
                              onChanged: (v) => setState(() {}),
                            ),

                            const SizedBox(height: 32),
                            
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _createProfile,
                                style: FilledButton.styleFrom(
                                  backgroundColor: activeConfig.color,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  elevation: 8,
                                  shadowColor: activeConfig.shadowColor,
                                ),
                                child: _isLoading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(
                                      _inviteCodeController.text.length == 6 ? "Join Team" : "Create Profile",
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            Center(
                              child: TextButton(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                                child: Text(
                                  "Already have an account? Sign In",
                                  style: TextStyle(color: activeConfig.color, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int? maxLength,
    bool filled = false,
    Color? fillColor,
    Color? borderColor,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      validator: validator,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 22),
        suffixIcon: suffixIcon,
        filled: filled,
        fillColor: fillColor,
        counterText: "",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.black12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2)),
        floatingLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      textCapitalization: label == "Invite Code" ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: label == "Invite Code" ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]'))] : null,
    );
  }

  Widget _buildPurposeItem(PurposeConfig config) {
    bool isSelected = _selectedPurpose == config.id;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPurpose = config.id;
        _inviteCodeController.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isSelected ? config.color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.transparent : (Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12)),
          boxShadow: isSelected ? [BoxShadow(color: config.color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(config.icon, color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 28),
            const SizedBox(height: 8),
            Text(
              config.name,
              style: TextStyle(
                color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
