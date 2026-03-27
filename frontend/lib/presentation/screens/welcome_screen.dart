import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/data/providers/app_providers.dart';
import '../widgets/premium_card.dart';
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
    const primaryColor = Color(0xFF6366F1); // Fixed indigo

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
            ),
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
                            "Manager",
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
                              "Create Your Account",
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "All fields below are required",
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 24),
                            
                            _buildTextField(
                              controller: _nameController,
                              label: "Full Name",
                              icon: Icons.person_rounded,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return "Name is required";
                                if (v.trim().length < 2) return "Name must be at least 2 characters";
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _emailController,
                              label: "Email Address",
                              icon: Icons.email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return "Email is required";
                                if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(v.trim())) {
                                  return "Enter a valid email (e.g. name@gmail.com)";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: "Phone Number",
                              icon: Icons.phone_rounded,
                              keyboardType: TextInputType.phone,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return "Phone number is required";
                                if (v.trim().length < 10) return "Enter a valid phone number (min 10 digits)";
                                return null;
                              },
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
                              validator: (v) {
                                if (v == null || v.isEmpty) return "Password is required";
                                if (v.length < 6) return "Password must be at least 6 characters";
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 32),
                            
                            _buildTextField(
                              controller: _inviteCodeController,
                              label: "Invite Code (Optional)",
                              icon: Icons.qr_code_rounded,
                              hint: "ABC123",
                              maxLength: 6,
                              filled: true,
                              fillColor: const Color(0xFF6366F1).withOpacity(0.05),
                              borderColor: const Color(0xFF6366F1).withOpacity(0.1),
                              onChanged: (v) => setState(() {}),
                            ),

                            const SizedBox(height: 32),
                            
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _createProfile,
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  elevation: 8,
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
                                child: const Text(
                                  "Already have an account? Sign In",
                                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.w700),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2)),
        floatingLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      textCapitalization: label == "Invite Code (Optional)" ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: label == "Invite Code (Optional)" ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]'))] : null,
    );
  }
}
